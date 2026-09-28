import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

enum BiometricType { fingerprint, face, iris, strong, weak, unknown }

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Whether the device can host an unlock prompt at all.
  ///
  /// This uses `isDeviceSupported()`, NOT `canCheckBiometrics`.
  /// `canCheckBiometrics` answers "are there enrolled *biometrics*", so it is
  /// false on a perfectly good device that only has a PIN/pattern/passcode
  /// enrolled. Gating on it refused to even show the prompt in exactly the
  /// case where the documented device-credential fallback was the only way
  /// forward. `isDeviceSupported` asks the right question: can this platform
  /// present a credential prompt (biometric or device credential) here?
  static Future<bool> isBiometricAvailable() async {
    try {
      if (await _auth.isDeviceSupported()) return true;
      // Some platform implementations (notably older Android) leave
      // `isDeviceSupported` false while `canCheckBiometrics` still reports
      // usable hardware, so treat either signal as sufficient.
      return await _auth.canCheckBiometrics;
    } on LocalAuthException catch (e) {
      debugPrint('Biometric availability check failed: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('Biometric availability check failed: $e');
      return false;
    }
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      final available = await _auth.getAvailableBiometrics();
      return available.map(_mapBiometricType).toList();
    } catch (e) {
      debugPrint('Failed to get available biometrics: $e');
      return [];
    }
  }

  static BiometricType _mapBiometricType(dynamic type) {
    // local_auth 3.x returns BiometricType enum from the plugin
    if (type == null) return BiometricType.unknown;
    final typeStr = type.toString().split('.').last;
    switch (typeStr) {
      case 'fingerprint':
        return BiometricType.fingerprint;
      case 'face':
        return BiometricType.face;
      case 'iris':
        return BiometricType.iris;
      case 'strong':
        return BiometricType.strong;
      case 'weak':
        return BiometricType.weak;
      default:
        return BiometricType.unknown;
    }
  }

  static Future<BiometricType?> getEnabledBiometricType() async {
    final typeStr = await SecureStorageService.getBiometricType();
    if (typeStr == null) return null;
    return BiometricType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => BiometricType.unknown,
    );
  }

  static Future<void> disableBiometric() async {
    await SecureStorageService.setBiometricEnabled(false);
  }

  static Future<BiometricAuthResult> authenticate({
    required String localizedReason,
    bool useErrorDialogs = true,
    bool stickyAuth = true,
    bool sensitiveTransaction = false,
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.notAvailable,
          errorMessage:
              'Biometric authentication is not available on this device',
        );
      }
      final availableBiometrics = await getAvailableBiometrics();
      // NOTE: an empty list is NOT a failure. `biometricOnly: false` below
      // means the user may satisfy the prompt with a device PIN / pattern /
      // passcode, which is the documented fallback and the only option on a
      // device with a screen lock but no enrolled fingerprint/face. The old
      // check returned `notEnrolled` here and made that fallback unreachable,
      // locking the user out of an app they had legitimately enabled the lock
      // on. Enrollment is reported by the plugin itself, as a typed
      // `noBiometricsEnrolled` LocalAuthException, when it genuinely applies.
      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        // Allow device-credential fallback (PIN/pattern/passcode) where the
        // device supports it, in addition to enrolled biometrics.
        biometricOnly: false,
        sensitiveTransaction: sensitiveTransaction,
        persistAcrossBackgrounding: stickyAuth,
      );
      if (authenticated) {
        await SecureStorageService.setBiometricEnabled(true);
        // The modal can succeed via device credential with nothing enrolled, so
        // this is optional rather than `availableBiometrics.first`.
        final biometricType = availableBiometrics.isEmpty
            ? null
            : availableBiometrics.first;
        if (biometricType != null) {
          await SecureStorageService.setBiometricType(biometricType.name);
        }
        return BiometricAuthResult(success: true, biometricType: biometricType);
      } else {
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.userCancel,
          errorMessage: 'Authentication was cancelled by user',
        );
      }
    } on LocalAuthException catch (e) {
      // local_auth 3.x throws a typed exception, NOT a PlatformException. The
      // old `on PlatformException` handler below never fired for real plugin
      // failures, so every genuine error fell through to the generic catch and
      // the user was shown a raw `LocalAuthException(code ...)` string.
      return _mapLocalAuthException(e);
    } on PlatformException catch (e) {
      // Retained for safety: a platform channel error can still surface as a
      // PlatformException before the plugin's own translation runs.
      return BiometricAuthResult(
        success: false,
        errorCode: BiometricAuthErrorCode.unknown,
        errorMessage: e.message ?? 'Unknown error',
      );
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return BiometricAuthResult(
        success: false,
        errorCode: BiometricAuthErrorCode.unknown,
        errorMessage: 'Biometric authentication is not available',
      );
    }
  }

  /// Map a typed [LocalAuthException] onto the app's own error enum.
  ///
  /// Deliberately does not echo `e.description` to the UI: descriptions are
  /// developer-facing plugin strings and one of them is the FragmentActivity
  /// message, which would tell the user nothing actionable.
  /// Test-only entry point onto [_mapLocalAuthException].
  ///
  /// The mapper is private because production code should never call it
  /// directly — it is reached through the `on LocalAuthException` handler in
  /// [authenticate]. Exposing it here lets the error mapping be regression
  /// tested without a device, which is the only environment these tests run in.
  @visibleForTesting
  static BiometricAuthResult mapExceptionForTest(LocalAuthException e) =>
      _mapLocalAuthException(e);

  static BiometricAuthResult _mapLocalAuthException(LocalAuthException e) {
    debugPrint('Biometric error: ${e.code} ${e.description}');
    switch (e.code) {
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.notEnrolled,
          errorMessage: 'No biometrics enrolled',
        );
      case LocalAuthExceptionCode.noBiometricHardware:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.notAvailable,
          errorMessage: 'This device has no biometric hardware',
        );
      case LocalAuthExceptionCode.noCredentialsSet:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.passcodeNotSet,
          errorMessage: 'Device passcode is not set',
        );
      case LocalAuthExceptionCode.temporaryLockout:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.lockedOut,
          errorMessage: 'Biometric authentication locked out',
        );
      case LocalAuthExceptionCode.biometricLockout:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.permanentlyLockedOut,
          errorMessage: 'Biometric authentication permanently locked out',
        );
      case LocalAuthExceptionCode.userCanceled:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.userCancel,
          errorMessage: 'Authentication was cancelled',
        );
      case LocalAuthExceptionCode.systemCanceled:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.systemCancel,
          errorMessage: 'Authentication was cancelled by the system',
        );
      case LocalAuthExceptionCode.uiUnavailable:
        // The activity is not able to host the prompt (almost always: not a
        // FragmentActivity). Not user-fixable, so it must not be reported as
        // "no biometrics enrolled" or the user will go and change settings
        // that are already correct.
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.notAvailable,
          errorMessage: 'Biometric prompt unavailable on this build',
        );
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.notAvailable,
          errorMessage: 'Biometric hardware is temporarily unavailable',
        );
      case LocalAuthExceptionCode.timeout:
      case LocalAuthExceptionCode.authInProgress:
      case LocalAuthExceptionCode.deviceError:
      case LocalAuthExceptionCode.unknownError:
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.unknown,
          errorMessage: 'Biometric authentication failed',
        );
      case LocalAuthExceptionCode.userRequestedFallback:
        // The user picked the device-credential option in the system sheet and
        // it did not complete. Treated as a cancellation, not a failure, so
        // the retry button is offered rather than an error the user cannot act
        // on.
        return BiometricAuthResult(
          success: false,
          errorCode: BiometricAuthErrorCode.userCancel,
          errorMessage: 'Authentication was cancelled',
        );
    }
  }

  static Future<bool> isBiometricEnabled() async {
    return await SecureStorageService.isBiometricEnabled();
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    await SecureStorageService.setBiometricEnabled(enabled);
  }
}

class BiometricAuthResult {
  final bool success;
  final BiometricType? biometricType;
  final BiometricAuthErrorCode? errorCode;
  final String? errorMessage;
  BiometricAuthResult({
    required this.success,
    this.biometricType,
    this.errorCode,
    this.errorMessage,
  });
}

enum BiometricAuthErrorCode {
  notAvailable,
  notEnrolled,
  lockedOut,
  permanentlyLockedOut,
  userCancel,
  systemCancel,
  passcodeNotSet,
  unknown,
}
