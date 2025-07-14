package com.reactnativeecommercetask

import com.facebook.react.bridge.*
import com.google.firebase.auth.FirebaseAuth

class AuthModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    private val auth: FirebaseAuth = FirebaseAuth.getInstance()

    override fun getName(): String {
        return "AuthModule"
    }

    @ReactMethod
    fun register(email: String, password: String, promise: Promise) {
        auth.createUserWithEmailAndPassword(email, password)
            .addOnSuccessListener {
                promise.resolve("success")
            }
            .addOnFailureListener { e ->
                promise.reject("REGISTER_ERROR", e.message)
            }
    }

    @ReactMethod
    fun login(email: String, password: String, promise: Promise) {
        auth.signInWithEmailAndPassword(email, password)
            .addOnSuccessListener {
                promise.resolve("success")
            }
            .addOnFailureListener { e ->
                promise.reject("LOGIN_ERROR", e.message)
            }
    }

    @ReactMethod
    fun logout(promise: Promise) {
        auth.signOut()
        promise.resolve("success")
    }
}
