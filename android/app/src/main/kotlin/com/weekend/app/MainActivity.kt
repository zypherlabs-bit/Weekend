package com.weekend.app

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Weekend's single Android entry point.
 *
 * Why FlutterFragmentActivity and not FlutterActivity
 * ---------------------------------------------------
 * This MUST be a `FlutterFragmentActivity`. `local_auth_android` hosts the
 * AndroidX `BiometricPrompt` through a fragment and checks the foreground
 * activity before it will show anything. Against a plain `FlutterActivity`
 * (which extends `android.app.Activity`, not `FragmentActivity`) the plugin
 * returns `NOT_FRAGMENT_ACTIVITY`, surfaced to Dart as:
 *
 *     LocalAuthException(code: uiUnavailable,
 *                        description: 'The current Activity must be a
 *                                      FragmentActivity.')
 *
 * which meant the biometric app lock could never open a prompt on Android.
 * `FlutterFragmentActivity` extends `FragmentActivity` (and, transitively,
 * `ComponentActivity`), so it satisfies that check. This is the same class
 * AndroidX itself documents for `BiometricPrompt`.
 *
 * Screen-capture protection
 * -------------------------
 * `FLAG_SECURE` is applied to the one activity that hosts the whole Flutter
 * UI, before the engine attaches.  This covers discovery, profiles, likes,
 * chats, settings and the recent-apps thumbnail.  It is a supported Android
 * defense, not a guarantee: a camera pointed at the screen, or an OEM that
 * ignores the flag, is outside the platform contract.
 *
 * Predictive back
 * ---------------
 * No back-handling code belongs here.  The embedding already routes back
 * gestures into Dart via `PopScope` / GoRouter, and registering a second
 * callback risks replacing Flutter's handler.
 */
class MainActivity : FlutterFragmentActivity() {

    private var vpnSecurityChannel: VpnSecurityChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Protect the entire app window.  Re-applied on every activity
        // recreation (rotation, process restore), so it cannot be lost by
        // navigating or backgrounding.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Belt-and-braces on Android 13+: keep the app out of the recents
            // screenshot even on launchers that ignore FLAG_SECURE thumbnails.
            setRecentsScreenshotEnabled(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vpnSecurityChannel = VpnSecurityChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.attach() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        vpnSecurityChannel?.dispose()
        vpnSecurityChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        vpnSecurityChannel?.dispose()
        vpnSecurityChannel = null
        super.onDestroy()
    }
}
