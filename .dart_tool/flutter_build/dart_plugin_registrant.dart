//
// Generated file. Do not edit.
// This file is generated from template in file `flutter_tools/lib/src/flutter_plugins.dart`.
//

// @dart = 3.11

import 'dart:io'; // flutter_ignore: dart_io_import.
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as flutter_local_notifications;
import 'package:geocoding_android/geocoding_android.dart' as geocoding_android;
import 'package:geolocator_android/geolocator_android.dart' as geolocator_android;
import 'package:image_editor_common/image_editor_common.dart' as image_editor_common;
import 'package:image_picker_android/image_picker_android.dart' as image_picker_android;
import 'package:path_provider_android/path_provider_android.dart' as path_provider_android;
import 'package:shared_preferences_android/shared_preferences_android.dart' as shared_preferences_android;
import 'package:sqflite_android/sqflite_android.dart' as sqflite_android;
import 'package:url_launcher_android/url_launcher_android.dart' as url_launcher_android;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as flutter_local_notifications;
import 'package:geocoding_ios/geocoding_ios.dart' as geocoding_ios;
import 'package:geolocator_apple/geolocator_apple.dart' as geolocator_apple;
import 'package:image_editor_common/image_editor_common.dart' as image_editor_common;
import 'package:image_picker_ios/image_picker_ios.dart' as image_picker_ios;
import 'package:path_provider_foundation/path_provider_foundation.dart' as path_provider_foundation;
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart' as shared_preferences_foundation;
import 'package:sqflite_darwin/sqflite_darwin.dart' as sqflite_darwin;
import 'package:url_launcher_ios/url_launcher_ios.dart' as url_launcher_ios;
import 'package:app_links_linux/app_links_linux.dart' as app_links_linux;
import 'package:connectivity_plus/connectivity_plus.dart' as connectivity_plus;
import 'package:file_selector_linux/file_selector_linux.dart' as file_selector_linux;
import 'package:flutter_local_notifications_linux/flutter_local_notifications_linux.dart' as flutter_local_notifications_linux;
import 'package:image_picker_linux/image_picker_linux.dart' as image_picker_linux;
import 'package:path_provider_linux/path_provider_linux.dart' as path_provider_linux;
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:shared_preferences_linux/shared_preferences_linux.dart' as shared_preferences_linux;
import 'package:url_launcher_linux/url_launcher_linux.dart' as url_launcher_linux;
import 'package:file_selector_macos/file_selector_macos.dart' as file_selector_macos;
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as flutter_local_notifications;
import 'package:geolocator_apple/geolocator_apple.dart' as geolocator_apple;
import 'package:image_editor_common/image_editor_common.dart' as image_editor_common;
import 'package:image_picker_macos/image_picker_macos.dart' as image_picker_macos;
import 'package:path_provider_foundation/path_provider_foundation.dart' as path_provider_foundation;
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart' as shared_preferences_foundation;
import 'package:sqflite_darwin/sqflite_darwin.dart' as sqflite_darwin;
import 'package:url_launcher_macos/url_launcher_macos.dart' as url_launcher_macos;
import 'package:file_selector_windows/file_selector_windows.dart' as file_selector_windows;
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart' as flutter_secure_storage_windows;
import 'package:image_picker_windows/image_picker_windows.dart' as image_picker_windows;
import 'package:path_provider_windows/path_provider_windows.dart' as path_provider_windows;
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:shared_preferences_windows/shared_preferences_windows.dart' as shared_preferences_windows;
import 'package:url_launcher_windows/url_launcher_windows.dart' as url_launcher_windows;

@pragma('vm:entry-point')
class _PluginRegistrant {

  @pragma('vm:entry-point')
  static void register() {
    if (Platform.isAndroid) {
      try {
        flutter_local_notifications.AndroidFlutterLocalNotificationsPlugin.registerWith();
      } catch (err) {
        print(
          '`flutter_local_notifications` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        geocoding_android.GeocodingAndroid.registerWith();
      } catch (err) {
        print(
          '`geocoding_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        geolocator_android.GeolocatorAndroid.registerWith();
      } catch (err) {
        print(
          '`geolocator_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_editor_common.ImageEditorCommon.registerWith();
      } catch (err) {
        print(
          '`image_editor_common` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_picker_android.ImagePickerAndroid.registerWith();
      } catch (err) {
        print(
          '`image_picker_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_android.PathProviderAndroid.registerWith();
      } catch (err) {
        print(
          '`path_provider_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_android.SharedPreferencesAndroid.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        sqflite_android.SqfliteAndroid.registerWith();
      } catch (err) {
        print(
          '`sqflite_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_android.UrlLauncherAndroid.registerWith();
      } catch (err) {
        print(
          '`url_launcher_android` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isIOS) {
      try {
        flutter_local_notifications.IOSFlutterLocalNotificationsPlugin.registerWith();
      } catch (err) {
        print(
          '`flutter_local_notifications` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        geocoding_ios.GeocodingIOS.registerWith();
      } catch (err) {
        print(
          '`geocoding_ios` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        geolocator_apple.GeolocatorApple.registerWith();
      } catch (err) {
        print(
          '`geolocator_apple` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_editor_common.ImageEditorCommon.registerWith();
      } catch (err) {
        print(
          '`image_editor_common` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_picker_ios.ImagePickerIOS.registerWith();
      } catch (err) {
        print(
          '`image_picker_ios` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_foundation.PathProviderFoundation.registerWith();
      } catch (err) {
        print(
          '`path_provider_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_foundation.SharedPreferencesFoundation.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        sqflite_darwin.SqfliteDarwin.registerWith();
      } catch (err) {
        print(
          '`sqflite_darwin` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_ios.UrlLauncherIOS.registerWith();
      } catch (err) {
        print(
          '`url_launcher_ios` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isLinux) {
      try {
        app_links_linux.AppLinksPluginLinux.registerWith();
      } catch (err) {
        print(
          '`app_links_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        connectivity_plus.ConnectivityPlusLinuxPlugin.registerWith();
      } catch (err) {
        print(
          '`connectivity_plus` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        file_selector_linux.FileSelectorLinux.registerWith();
      } catch (err) {
        print(
          '`file_selector_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_local_notifications_linux.LinuxFlutterLocalNotificationsPlugin.registerWith();
      } catch (err) {
        print(
          '`flutter_local_notifications_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_picker_linux.ImagePickerLinux.registerWith();
      } catch (err) {
        print(
          '`image_picker_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_linux.PathProviderLinux.registerWith();
      } catch (err) {
        print(
          '`path_provider_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        share_plus.SharePlusLinuxPlugin.registerWith();
      } catch (err) {
        print(
          '`share_plus` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_linux.SharedPreferencesLinux.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_linux.UrlLauncherLinux.registerWith();
      } catch (err) {
        print(
          '`url_launcher_linux` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isMacOS) {
      try {
        file_selector_macos.FileSelectorMacOS.registerWith();
      } catch (err) {
        print(
          '`file_selector_macos` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_local_notifications.MacOSFlutterLocalNotificationsPlugin.registerWith();
      } catch (err) {
        print(
          '`flutter_local_notifications` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        geolocator_apple.GeolocatorApple.registerWith();
      } catch (err) {
        print(
          '`geolocator_apple` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_editor_common.ImageEditorCommon.registerWith();
      } catch (err) {
        print(
          '`image_editor_common` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_picker_macos.ImagePickerMacOS.registerWith();
      } catch (err) {
        print(
          '`image_picker_macos` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_foundation.PathProviderFoundation.registerWith();
      } catch (err) {
        print(
          '`path_provider_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_foundation.SharedPreferencesFoundation.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_foundation` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        sqflite_darwin.SqfliteDarwin.registerWith();
      } catch (err) {
        print(
          '`sqflite_darwin` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_macos.UrlLauncherMacOS.registerWith();
      } catch (err) {
        print(
          '`url_launcher_macos` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    } else if (Platform.isWindows) {
      try {
        file_selector_windows.FileSelectorWindows.registerWith();
      } catch (err) {
        print(
          '`file_selector_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        flutter_secure_storage_windows.FlutterSecureStorageWindows.registerWith();
      } catch (err) {
        print(
          '`flutter_secure_storage_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        image_picker_windows.ImagePickerWindows.registerWith();
      } catch (err) {
        print(
          '`image_picker_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        path_provider_windows.PathProviderWindows.registerWith();
      } catch (err) {
        print(
          '`path_provider_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        share_plus.SharePlusWindowsPlugin.registerWith();
      } catch (err) {
        print(
          '`share_plus` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        shared_preferences_windows.SharedPreferencesWindows.registerWith();
      } catch (err) {
        print(
          '`shared_preferences_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

      try {
        url_launcher_windows.UrlLauncherWindows.registerWith();
      } catch (err) {
        print(
          '`url_launcher_windows` threw an error: $err. '
          'The app may not function as expected until you remove this plugin from pubspec.yaml'
        );
      }

    }
  }
}
