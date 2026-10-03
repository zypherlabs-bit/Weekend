// GENERATED CODE - MANUAL PLACEHOLDER
// This file should be replaced with `flutterfire configure` once a Firebase
// project is set up for Weekend. Until then, the app uses local notifications
// only (foreground notifications via the `notifications` table + Realtime).
//
// To generate the real file:
//   dart pub global activate flutterfire_cli
//   flutterfire configure \
//     --project=<firebase-project-id> \
//     --out=lib/firebase_options.dart

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase has not been configured for web. Run `flutterfire configure` '
        'and set WEEKEND_FIREBASE_WEB_API_KEY in your environment.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'Firebase has not been configured for iOS. Run `flutterfire configure`.',
        );
      default:
        throw UnsupportedError(
          'Firebase has not been configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: String.fromEnvironment('WEEKEND_FIREBASE_ANDROID_API_KEY'),
    appId: String.fromEnvironment('WEEKEND_FIREBASE_ANDROID_APP_ID'),
    messagingSenderId: String.fromEnvironment('WEEKEND_FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('WEEKEND_FIREBASE_PROJECT_ID'),
    storageBucket: String.fromEnvironment('WEEKEND_FIREBASE_STORAGE_BUCKET'),
  );
}
