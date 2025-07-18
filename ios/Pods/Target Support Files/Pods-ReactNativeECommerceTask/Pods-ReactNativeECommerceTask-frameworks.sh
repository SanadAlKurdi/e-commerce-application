#!/bin/sh
set -e
set -u
set -o pipefail

function on_error {
  echo "$(realpath -mq "${0}"):$1: error: Unexpected failure"
}
trap 'on_error $LINENO' ERR

if [ -z ${FRAMEWORKS_FOLDER_PATH+x} ]; then
  # If FRAMEWORKS_FOLDER_PATH is not set, then there's nowhere for us to copy
  # frameworks to, so exit 0 (signalling the script phase was successful).
  exit 0
fi

echo "mkdir -p ${CONFIGURATION_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "${CONFIGURATION_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

COCOAPODS_PARALLEL_CODE_SIGN="${COCOAPODS_PARALLEL_CODE_SIGN:-false}"
SWIFT_STDLIB_PATH="${TOOLCHAIN_DIR}/usr/lib/swift/${PLATFORM_NAME}"
BCSYMBOLMAP_DIR="BCSymbolMaps"


# This protects against multiple targets copying the same framework dependency at the same time. The solution
# was originally proposed here: https://lists.samba.org/archive/rsync/2008-February/020158.html
RSYNC_PROTECT_TMP_FILES=(--filter "P .*.??????")

# Copies and strips a vendored framework
install_framework()
{
  if [ -r "${BUILT_PRODUCTS_DIR}/$1" ]; then
    local source="${BUILT_PRODUCTS_DIR}/$1"
  elif [ -r "${BUILT_PRODUCTS_DIR}/$(basename "$1")" ]; then
    local source="${BUILT_PRODUCTS_DIR}/$(basename "$1")"
  elif [ -r "$1" ]; then
    local source="$1"
  fi

  local destination="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"

  if [ -L "${source}" ]; then
    echo "Symlinked..."
    source="$(readlink -f "${source}")"
  fi

  if [ -d "${source}/${BCSYMBOLMAP_DIR}" ]; then
    # Locate and install any .bcsymbolmaps if present, and remove them from the .framework before the framework is copied
    find "${source}/${BCSYMBOLMAP_DIR}" -name "*.bcsymbolmap"|while read f; do
      echo "Installing $f"
      install_bcsymbolmap "$f" "$destination"
      rm "$f"
    done
    rmdir "${source}/${BCSYMBOLMAP_DIR}"
  fi

  # Use filter instead of exclude so missing patterns don't throw errors.
  echo "rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --links --filter \"- CVS/\" --filter \"- .svn/\" --filter \"- .git/\" --filter \"- .hg/\" --filter \"- Headers\" --filter \"- PrivateHeaders\" --filter \"- Modules\" \"${source}\" \"${destination}\""
  rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --links --filter "- CVS/" --filter "- .svn/" --filter "- .git/" --filter "- .hg/" --filter "- Headers" --filter "- PrivateHeaders" --filter "- Modules" "${source}" "${destination}"

  local basename
  basename="$(basename -s .framework "$1")"
  binary="${destination}/${basename}.framework/${basename}"

  if ! [ -r "$binary" ]; then
    binary="${destination}/${basename}"
  elif [ -L "${binary}" ]; then
    echo "Destination binary is symlinked..."
    dirname="$(dirname "${binary}")"
    binary="${dirname}/$(readlink "${binary}")"
  fi

  # Strip invalid architectures so "fat" simulator / device frameworks work on device
  if [[ "$(file "$binary")" == *"dynamically linked shared library"* ]]; then
    strip_invalid_archs "$binary"
  fi

  # Resign the code if required by the build settings to avoid unstable apps
  code_sign_if_enabled "${destination}/$(basename "$1")"

  # Embed linked Swift runtime libraries. No longer necessary as of Xcode 7.
  if [ "${XCODE_VERSION_MAJOR}" -lt 7 ]; then
    local swift_runtime_libs
    swift_runtime_libs=$(xcrun otool -LX "$binary" | grep --color=never @rpath/libswift | sed -E s/@rpath\\/\(.+dylib\).*/\\1/g | uniq -u)
    for lib in $swift_runtime_libs; do
      echo "rsync -auv \"${SWIFT_STDLIB_PATH}/${lib}\" \"${destination}\""
      rsync -auv "${SWIFT_STDLIB_PATH}/${lib}" "${destination}"
      code_sign_if_enabled "${destination}/${lib}"
    done
  fi
}
# Copies and strips a vendored dSYM
install_dsym() {
  local source="$1"
  warn_missing_arch=${2:-true}
  if [ -r "$source" ]; then
    # Copy the dSYM into the targets temp dir.
    echo "rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --filter \"- CVS/\" --filter \"- .svn/\" --filter \"- .git/\" --filter \"- .hg/\" --filter \"- Headers\" --filter \"- PrivateHeaders\" --filter \"- Modules\" \"${source}\" \"${DERIVED_FILES_DIR}\""
    rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --filter "- CVS/" --filter "- .svn/" --filter "- .git/" --filter "- .hg/" --filter "- Headers" --filter "- PrivateHeaders" --filter "- Modules" "${source}" "${DERIVED_FILES_DIR}"

    local basename
    basename="$(basename -s .dSYM "$source")"
    binary_name="$(ls "$source/Contents/Resources/DWARF")"
    binary="${DERIVED_FILES_DIR}/${basename}.dSYM/Contents/Resources/DWARF/${binary_name}"

    # Strip invalid architectures from the dSYM.
    if [[ "$(file "$binary")" == *"Mach-O "*"dSYM companion"* ]]; then
      strip_invalid_archs "$binary" "$warn_missing_arch"
    fi
    if [[ $STRIP_BINARY_RETVAL == 0 ]]; then
      # Move the stripped file into its final destination.
      echo "rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --links --filter \"- CVS/\" --filter \"- .svn/\" --filter \"- .git/\" --filter \"- .hg/\" --filter \"- Headers\" --filter \"- PrivateHeaders\" --filter \"- Modules\" \"${DERIVED_FILES_DIR}/${basename}.framework.dSYM\" \"${DWARF_DSYM_FOLDER_PATH}\""
      rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --links --filter "- CVS/" --filter "- .svn/" --filter "- .git/" --filter "- .hg/" --filter "- Headers" --filter "- PrivateHeaders" --filter "- Modules" "${DERIVED_FILES_DIR}/${basename}.dSYM" "${DWARF_DSYM_FOLDER_PATH}"
    else
      # The dSYM was not stripped at all, in this case touch a fake folder so the input/output paths from Xcode do not reexecute this script because the file is missing.
      mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
      touch "${DWARF_DSYM_FOLDER_PATH}/${basename}.dSYM"
    fi
  fi
}

# Used as a return value for each invocation of `strip_invalid_archs` function.
STRIP_BINARY_RETVAL=0

# Strip invalid architectures
strip_invalid_archs() {
  binary="$1"
  warn_missing_arch=${2:-true}
  # Get architectures for current target binary
  binary_archs="$(lipo -info "$binary" | rev | cut -d ':' -f1 | awk '{$1=$1;print}' | rev)"
  # Intersect them with the architectures we are building for
  intersected_archs="$(echo ${ARCHS[@]} ${binary_archs[@]} | tr ' ' '\n' | sort | uniq -d)"
  # If there are no archs supported by this binary then warn the user
  if [[ -z "$intersected_archs" ]]; then
    if [[ "$warn_missing_arch" == "true" ]]; then
      echo "warning: [CP] Vendored binary '$binary' contains architectures ($binary_archs) none of which match the current build architectures ($ARCHS)."
    fi
    STRIP_BINARY_RETVAL=1
    return
  fi
  stripped=""
  for arch in $binary_archs; do
    if ! [[ "${ARCHS}" == *"$arch"* ]]; then
      # Strip non-valid architectures in-place
      lipo -remove "$arch" -output "$binary" "$binary"
      stripped="$stripped $arch"
    fi
  done
  if [[ "$stripped" ]]; then
    echo "Stripped $binary of architectures:$stripped"
  fi
  STRIP_BINARY_RETVAL=0
}

# Copies the bcsymbolmap files of a vendored framework
install_bcsymbolmap() {
    local bcsymbolmap_path="$1"
    local destination="${BUILT_PRODUCTS_DIR}"
    echo "rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --filter "- CVS/" --filter "- .svn/" --filter "- .git/" --filter "- .hg/" --filter "- Headers" --filter "- PrivateHeaders" --filter "- Modules" "${bcsymbolmap_path}" "${destination}""
    rsync --delete -av "${RSYNC_PROTECT_TMP_FILES[@]}" --filter "- CVS/" --filter "- .svn/" --filter "- .git/" --filter "- .hg/" --filter "- Headers" --filter "- PrivateHeaders" --filter "- Modules" "${bcsymbolmap_path}" "${destination}"
}

# Signs a framework with the provided identity
code_sign_if_enabled() {
  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" -a "${CODE_SIGNING_REQUIRED:-}" != "NO" -a "${CODE_SIGNING_ALLOWED}" != "NO" ]; then
    # Use the current code_sign_identity
    echo "Code Signing $1 with Identity ${EXPANDED_CODE_SIGN_IDENTITY_NAME}"
    local code_sign_cmd="/usr/bin/codesign --force --sign ${EXPANDED_CODE_SIGN_IDENTITY} ${OTHER_CODE_SIGN_FLAGS:-} --preserve-metadata=identifier,entitlements '$1'"

    if [ "${COCOAPODS_PARALLEL_CODE_SIGN}" == "true" ]; then
      code_sign_cmd="$code_sign_cmd &"
    fi
    echo "$code_sign_cmd"
    eval "$code_sign_cmd"
  fi
}

if [[ "$CONFIGURATION" == "Debug" ]]; then
  install_framework "${BUILT_PRODUCTS_DIR}/BoringSSL-GRPC/openssl_grpc.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/DoubleConversion/DoubleConversion.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseAppCheckInterop/FirebaseAppCheckInterop.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseAuth/FirebaseAuth.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseAuthInterop/FirebaseAuthInterop.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseCore/FirebaseCore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseCoreExtension/FirebaseCoreExtension.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseCoreInternal/FirebaseCoreInternal.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseFirestore/FirebaseFirestore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseFirestoreInternal/FirebaseFirestoreInternal.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseSharedSwift/FirebaseSharedSwift.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseStorage/FirebaseStorage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/GTMSessionFetcher/GTMSessionFetcher.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/GoogleUtilities/GoogleUtilities.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RCT-Folly/folly.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RCTDeprecation/RCTDeprecation.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RCTTypeSafety/RCTTypeSafety.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNCAsyncStorage/RNCAsyncStorage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBApp/RNFBApp.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBAuth/RNFBAuth.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBFirestore/RNFBFirestore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBStorage/RNFBStorage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNGestureHandler/RNGestureHandler.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNReanimated/RNReanimated.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNScreens/RNScreens.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-Core/React.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-CoreModules/CoreModules.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-Fabric/React_Fabric.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-FabricComponents/React_FabricComponents.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-FabricImage/React_FabricImage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-ImageManager/React_ImageManager.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-Mapbuffer/React_Mapbuffer.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-NativeModulesApple/React_NativeModulesApple.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTAnimation/RCTAnimation.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTAppDelegate/React_RCTAppDelegate.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTBlob/RCTBlob.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTFBReactNativeSpec/FBReactNativeSpec.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTFabric/RCTFabric.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTImage/RCTImage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTLinking/RCTLinking.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTNetwork/RCTNetwork.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTRuntime/RCTRuntime.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTSettings/RCTSettings.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTText/RCTText.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTVibration/RCTVibration.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RuntimeApple/React_RuntimeApple.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RuntimeCore/React_RuntimeCore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RuntimeHermes/React_RuntimeHermes.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-cxxreact/cxxreact.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-debug/React_debug.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-defaultsnativemodule/React_defaultsnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-domnativemodule/React_domnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-featureflags/React_featureflags.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-featureflagsnativemodule/React_featureflagsnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-graphics/React_graphics.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-hermes/reacthermes.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-idlecallbacksnativemodule/idlecallbacksnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jserrorhandler/React_jserrorhandler.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsi/jsi.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsiexecutor/jsireact.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspector/jsinspector_modern.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspectorcdp/jsinspector_moderncdp.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspectornetwork/jsinspector_modernnetwork.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspectortracing/jsinspector_moderntracing.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsitooling/JSITooling.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-logger/logger.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-microtasksnativemodule/React_microtasksnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-oscompat/oscompat.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-perflogger/reactperflogger.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-performancetimeline/React_performancetimeline.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-rendererconsistency/React_rendererconsistency.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-renderercss/React_renderercss.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-rendererdebug/React_rendererdebug.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-runtimescheduler/React_runtimescheduler.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-utils/React_utils.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/ReactAppDependencyProvider/ReactAppDependencyProvider.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/ReactCodegen/ReactCodegen.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/ReactCommon/ReactCommon.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RecaptchaInterop/RecaptchaInterop.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/SocketRocket/SocketRocket.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/Yoga/yoga.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/abseil/absl.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/fmt/fmt.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/gRPC-C++/grpcpp.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/gRPC-Core/grpc.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/glog/glog.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/leveldb-library/leveldb.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/lottie-ios/Lottie.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/lottie-react-native/lottie_react_native.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/nanopb/nanopb.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/react-native-image-picker/react_native_image_picker.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/react-native-safe-area-context/react_native_safe_area_context.framework"
  install_framework "${PODS_XCFRAMEWORKS_BUILD_DIR}/hermes-engine/Pre-built/hermes.framework"
fi
if [[ "$CONFIGURATION" == "Release" ]]; then
  install_framework "${BUILT_PRODUCTS_DIR}/BoringSSL-GRPC/openssl_grpc.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/DoubleConversion/DoubleConversion.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseAppCheckInterop/FirebaseAppCheckInterop.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseAuth/FirebaseAuth.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseAuthInterop/FirebaseAuthInterop.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseCore/FirebaseCore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseCoreExtension/FirebaseCoreExtension.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseCoreInternal/FirebaseCoreInternal.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseFirestore/FirebaseFirestore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseFirestoreInternal/FirebaseFirestoreInternal.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseSharedSwift/FirebaseSharedSwift.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/FirebaseStorage/FirebaseStorage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/GTMSessionFetcher/GTMSessionFetcher.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/GoogleUtilities/GoogleUtilities.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RCT-Folly/folly.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RCTDeprecation/RCTDeprecation.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RCTTypeSafety/RCTTypeSafety.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNCAsyncStorage/RNCAsyncStorage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBApp/RNFBApp.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBAuth/RNFBAuth.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBFirestore/RNFBFirestore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNFBStorage/RNFBStorage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNGestureHandler/RNGestureHandler.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNReanimated/RNReanimated.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RNScreens/RNScreens.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-Core/React.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-CoreModules/CoreModules.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-Fabric/React_Fabric.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-FabricComponents/React_FabricComponents.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-FabricImage/React_FabricImage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-ImageManager/React_ImageManager.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-Mapbuffer/React_Mapbuffer.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-NativeModulesApple/React_NativeModulesApple.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTAnimation/RCTAnimation.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTAppDelegate/React_RCTAppDelegate.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTBlob/RCTBlob.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTFBReactNativeSpec/FBReactNativeSpec.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTFabric/RCTFabric.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTImage/RCTImage.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTLinking/RCTLinking.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTNetwork/RCTNetwork.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTRuntime/RCTRuntime.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTSettings/RCTSettings.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTText/RCTText.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RCTVibration/RCTVibration.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RuntimeApple/React_RuntimeApple.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RuntimeCore/React_RuntimeCore.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-RuntimeHermes/React_RuntimeHermes.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-cxxreact/cxxreact.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-debug/React_debug.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-defaultsnativemodule/React_defaultsnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-domnativemodule/React_domnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-featureflags/React_featureflags.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-featureflagsnativemodule/React_featureflagsnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-graphics/React_graphics.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-hermes/reacthermes.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-idlecallbacksnativemodule/idlecallbacksnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jserrorhandler/React_jserrorhandler.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsi/jsi.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsiexecutor/jsireact.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspector/jsinspector_modern.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspectorcdp/jsinspector_moderncdp.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspectornetwork/jsinspector_modernnetwork.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsinspectortracing/jsinspector_moderntracing.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-jsitooling/JSITooling.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-logger/logger.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-microtasksnativemodule/React_microtasksnativemodule.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-oscompat/oscompat.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-perflogger/reactperflogger.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-performancetimeline/React_performancetimeline.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-rendererconsistency/React_rendererconsistency.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-renderercss/React_renderercss.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-rendererdebug/React_rendererdebug.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-runtimescheduler/React_runtimescheduler.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/React-utils/React_utils.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/ReactAppDependencyProvider/ReactAppDependencyProvider.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/ReactCodegen/ReactCodegen.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/ReactCommon/ReactCommon.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/RecaptchaInterop/RecaptchaInterop.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/SocketRocket/SocketRocket.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/Yoga/yoga.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/abseil/absl.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/fmt/fmt.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/gRPC-C++/grpcpp.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/gRPC-Core/grpc.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/glog/glog.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/leveldb-library/leveldb.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/lottie-ios/Lottie.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/lottie-react-native/lottie_react_native.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/nanopb/nanopb.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/react-native-image-picker/react_native_image_picker.framework"
  install_framework "${BUILT_PRODUCTS_DIR}/react-native-safe-area-context/react_native_safe_area_context.framework"
  install_framework "${PODS_XCFRAMEWORKS_BUILD_DIR}/hermes-engine/Pre-built/hermes.framework"
fi
if [ "${COCOAPODS_PARALLEL_CODE_SIGN}" == "true" ]; then
  wait
fi
