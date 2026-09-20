import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/models.dart';
import 'package:weekend/providers/auth_provider.dart';

void main() {
  group('MfaAttemptLimiter', () {
    test('allows attempts under the limit and reports remaining', () {
      final limiter = MfaAttemptLimiter();

      expect(limiter.isLockedOut('factor-1'), isFalse);
      expect(limiter.remainingAttempts('factor-1'), MfaAttemptLimiter.maxAttempts);

      expect(limiter.registerAttempt('factor-1'), isTrue);
      expect(limiter.registerAttempt('factor-1'), isTrue);
      expect(limiter.remainingAttempts('factor-1'),
          MfaAttemptLimiter.maxAttempts - 2);
      expect(limiter.isLockedOut('factor-1'), isFalse);
    });

    test('locks out after max attempts and recovers after reset', () {
      final limiter = MfaAttemptLimiter();

      for (var i = 0; i < MfaAttemptLimiter.maxAttempts - 1; i++) {
        expect(limiter.registerAttempt('factor-2'), isTrue);
      }
      // The max-th attempt trips the lockout.
      expect(limiter.registerAttempt('factor-2'), isFalse);
      expect(limiter.isLockedOut('factor-2'), isTrue);
      expect(limiter.lockedUntil('factor-2'), isNotNull);

      limiter.reset('factor-2');
      expect(limiter.isLockedOut('factor-2'), isFalse);
      expect(limiter.remainingAttempts('factor-2'), MfaAttemptLimiter.maxAttempts);
    });

    test('tracks factors independently', () {
      final limiter = MfaAttemptLimiter();

      for (var i = 0; i < MfaAttemptLimiter.maxAttempts; i++) {
        limiter.registerAttempt('factor-a');
      }
      expect(limiter.isLockedOut('factor-a'), isTrue);
      expect(limiter.isLockedOut('factor-b'), isFalse);
    });
  });

  group('WeekendAuthState MFA fields', () {
    test('defaults carry no MFA gate', () {
      const state = WeekendAuthState(isLoading: true);
      expect(state.needsMfaChallenge, isFalse);
      expect(state.mfaEnabled, isFalse);
    });

    test('copyWith preserves and updates MFA fields', () {
      const state = WeekendAuthState(isLoading: false);
      final challenged = state.copyWith(needsMfaChallenge: true, mfaEnabled: true);
      expect(challenged.needsMfaChallenge, isTrue);
      expect(challenged.mfaEnabled, isTrue);

      final cleared = challenged.copyWith(needsMfaChallenge: false);
      expect(cleared.needsMfaChallenge, isFalse);
      expect(cleared.mfaEnabled, isTrue);
    });

    test('clearError drops stale errors without touching MFA gate', () {
      const state = WeekendAuthState(
        isLoading: false,
        error: 'Incorrect or expired code.',
        needsMfaChallenge: true,
        mfaEnabled: true,
      );
      final cleared = state.clearError();
      expect(cleared.error, isNull);
      expect(cleared.needsMfaChallenge, isTrue);
      expect(cleared.mfaEnabled, isTrue);
    });
  });
}
