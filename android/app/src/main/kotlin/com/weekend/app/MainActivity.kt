package com.weekend.app

import io.flutter.embedding.android.FlutterActivity

/**
 * Weekend's single Android entry point.
 *
 * Predictive back
 * ---------------
 * No back-handling code belongs here, and an earlier attempt to add some was
 * removed for two concrete reasons:
 *
 *  1. `enableOnBackInvokedCallback` is declared on
 *     `androidx.activity.ComponentActivity`, NOT on `android.app.Activity`,
 *     so it does not compile against `FlutterActivity` (which extends
 *     `android.app.Activity`). Switching to `FlutterFragmentActivity` to
 *     reach it changed which activity owns plugin registration for no gain.
 *  2. It was redundant even then: `FlutterActivity.registerOnBackInvokedCallback`
 *     is already invoked from the embedding's own `onCreate` on API 33+, and
 *     it routes the gesture into the Dart framework. A second registration
 *     risks replacing Flutter's handler.
 *
 * App-specific back behaviour (blocking a pop, confirming a discard) belongs
 * in the Dart layer via GoRouter's `PopScope` / `canPop`, not here.
 */
class MainActivity : FlutterActivity()





