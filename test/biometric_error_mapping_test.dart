import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:weekend/services/biometric_auth_service.dart';

/// Locks in the mapping from `local_auth` 3.x typed exceptions onto Weekend's
/// own [BiometricAuthErrorCode].
///
/// Regression context: the service used to catch `PlatformException` and switch
/// on 2.x-style string codes (`'NotAvailable'`, `'NotEnrolled'`, ...). local_auth
/// 3.x throws `LocalAuthException` with a typed `LocalAuthExceptionCode`, so
/// that handler never matched a real plugin failure. Everything fell through to
/// a bare `catch` that returned `e.toString()`, and the lock screen showed the
/// user a raw `LocalAuthException(code ..., ...)` string instead of anything
/// actionable.
void main() {
  group('Biometric error mapping', () {
    test('no enrolled biometrics maps to notEnrolled', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(
          code: LocalAuthExceptionCode.noBiometricsEnrolled,
        ),
      );
      expect(result.success, isFalse);
      expect(result.errorCode, BiometricAuthErrorCode.notEnrolled);
    });

    test('no biometric hardware maps to notAvailable', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(
          code: LocalAuthExceptionCode.noBiometricHardware,
        ),
      );
      expect(result.errorCode, BiometricAuthErrorCode.notAvailable);
    });

    test('no device credentials maps to passcodeNotSet', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(code: LocalAuthExceptionCode.noCredentialsSet),
      );
      expect(result.errorCode, BiometricAuthErrorCode.passcodeNotSet);
    });

    test('temporary lockout maps to lockedOut', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(code: LocalAuthExceptionCode.temporaryLockout),
      );
      expect(result.errorCode, BiometricAuthErrorCode.lockedOut);
    });

    test('permanent lockout maps to permanentlyLockedOut', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(code: LocalAuthExceptionCode.biometricLockout),
      );
      expect(result.errorCode, BiometricAuthErrorCode.permanentlyLockedOut);
    });

    test('user cancellation maps to userCancel', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      );
      expect(result.errorCode, BiometricAuthErrorCode.userCancel);
    });

    test('system cancellation maps to systemCancel', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(code: LocalAuthExceptionCode.systemCanceled),
      );
      expect(result.errorCode, BiometricAuthErrorCode.systemCancel);
    });

    // The specific error that made the feature unusable: a plain
    // FlutterActivity made the plugin refuse to show any prompt at all.
    test('uiUnavailable does not claim the user forgot to enrol', () {
      final result = BiometricAuthService.mapExceptionForTest(
        const LocalAuthException(
          code: LocalAuthExceptionCode.uiUnavailable,
          description: 'The current Activity must be a FragmentActivity.',
        ),
      );
      expect(result.errorCode, BiometricAuthErrorCode.notAvailable);
      expect(
        result.errorCode,
        isNot(BiometricAuthErrorCode.notEnrolled),
        reason: 'telling the user to enrol a fingerprint would be a dead end',
      );
    });

    // Guards every code at once, so a future local_auth addition cannot open a
    // silent gap that returns a raw plugin string to the user.
    test('every plugin code maps without leaking its description', () {
      for (final code in LocalAuthExceptionCode.values) {
        final result = BiometricAuthService.mapExceptionForTest(
          LocalAuthException(code: code, description: 'INTERNAL_PLUGN_STRING'),
        );
        expect(result.success, isFalse, reason: 'must never report success');
        expect(
          result.errorCode,
          isNotNull,
          reason: '$code must map to an error code',
        );
        expect(
          result.errorMessage,
          isNot(contains('INTERNAL_PLUGN_STRING')),
          reason: 'raw plugin text must not reach the UI for $code',
        );
      }
    });
  });
}
