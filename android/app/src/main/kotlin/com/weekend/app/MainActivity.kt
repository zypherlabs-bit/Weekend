package com.weekend.app

import io.flutter.embedding.android.FlutterFragmentActivity

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
 * Predictive back
 * ---------------
 * No back-handling code belongs here, and an earlier attempt to add some was
 * removed for two concrete reasons:
 *
 *  1. `enableOnBackInvokedCallback` is declared on
 *     `androidx.activity.ComponentActivity`, NOT on `android.app.Activity`,
 *     so it does not compile against `FlutterActivity`. This is no longer a
 *     reason to stay on `FlutterActivity`, because the biometric requirement
 *     above is a hard constraint and the predictive-back handler is not:
 *     `FlutterFragmentActivity` already inherits the
 *     `ComponentActivity` implementation, and the embedding still routes
 *     back gestures into Dart via `PopScope` / `canPop` in GoRouter.
 *  2. It would be redundant even if added by hand: the embedding invokes
 *     `registerOnBackInvokedCallback` itself on API 33+, so a second
 *     registration risks replacing Flutter's handler.
 *
 * App-specific back behaviour (blocking a pop, confirming a discard) belongs
 * in the Dart layer via GoRouter's `PopScope` / `canPop`, not here.
 */
class MainActivity : FlutterFragmentActivity()
