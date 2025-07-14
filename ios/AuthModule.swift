import Foundation
import FirebaseAuth
import React

@objc(AuthModule)
class AuthModule: NSObject, RCTBridgeModule {
  static func moduleName() -> String! {
    return "AuthModule"
  }

  static func requiresMainQueueSetup() -> Bool {
    return true
  }

  @objc
  func register(_ email: String,
                password: String,
                resolver resolve: @escaping RCTPromiseResolveBlock,
                rejecter reject: @escaping RCTPromiseRejectBlock) {
    Auth.auth().createUser(withEmail: email, password: password) { result, error in
      if let error = error {
        reject("REGISTER_ERROR", error.localizedDescription, error)
      } else {
        resolve("success")
      }
    }
  }

  @objc
  func login(_ email: String,
             password: String,
             resolver resolve: @escaping RCTPromiseResolveBlock,
             rejecter reject: @escaping RCTPromiseRejectBlock) {
    Auth.auth().signIn(withEmail: email, password: password) { result, error in
      if let error = error {
        reject("LOGIN_ERROR", error.localizedDescription, error)
      } else {
        resolve("success")
      }
    }
  }

  @objc
  func logout(_ resolve: @escaping RCTPromiseResolveBlock,
              rejecter reject: @escaping RCTPromiseRejectBlock) {
    do {
      try Auth.auth().signOut()
      resolve("success")
    } catch let error {
      reject("LOGOUT_ERROR", "Failed to sign out", error)
    }
  }
}
