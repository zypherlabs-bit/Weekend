import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/services/app_lock_service.dart';

/// Regression tests for the reported defect: "leaving the app and coming back
/// does not show the fingerprint prompt".
///
/// These drive the state machine directly rather than the platform prompt, so
/// they run in CI. They prove the LOGIC that decides whether to prompt; they do
/// NOT prove that Android shows a BiometricPrompt, which needs a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLockService lifecycle', () {
    late AppLockService service;

    setUp(() {
      service = AppLockService.instance;
      service.debugReset();
      service.debugSetLockEnabled(true);
    });

    tearDown(() {
      service.debugReset();
      service.debugSetLockEnabled(false);
    });

    test('starts unlocked with the lock enabled', () {
      expect(service.isLocked, isFalse);
      expect(service.isLockEnabled, isTrue);
    });

    test('backgrounding locks the app immediately', () {
      service.debugHandleLifecycle(AppLifecycleState.paused);
      expect(service.isLocked, isTrue);
    });

    test('resuming after a real backgrounding stays locked', () {
      // The point of the whole feature: returning to the app must NOT leave it
      // open.
      service.debugHandleLifecycle(AppLifecycleState.paused);
      service.debugHandleLifecycle(AppLifecycleState.resumed);
      expect(
        service.isLocked,
        isTrue,
        reason: 'returning from the background must keep the app locked',
      );
    });

    test('REGRESSION: inactive must not arm the lock', () {
      // Android emits `inactive` every time a system surface takes focus -
      // including Android's own BiometricPrompt and Credential Manager sheet.
      // Treating it as backgrounding re-armed the lock while the prompt was on
      // screen and let an inactive->resumed pair unlock the app with no
      // authentication at all.
      service.debugHandleLifecycle(AppLifecycleState.inactive);
      expect(service.isLocked, isFalse);
      expect(service.isLocked, isFalse);
    });

    test('REGRESSION: inactive then resumed must NOT unlock a locked app', () {
      // The critical half of the previous bug.
      service.debugHandleLifecycle(AppLifecycleState.paused);
      expect(service.isLocked, isTrue);

      // A system sheet opens and closes: inactive -> resumed.
      service.debugHandleLifecycle(AppLifecycleState.inactive);
      service.debugHandleLifecycle(AppLifecycleState.resumed);

      expect(
        service.isLocked,
        isTrue,
        reason:
            'a system dialog appearing must not satisfy the app lock; only a '
            'real authentication may clear it',
      );
    });

    test('only a real authentication clears the lock', () {
      service.debugHandleLifecycle(AppLifecycleState.paused);
      expect(service.isLocked, isTrue);

      service.onAuthenticationSucceeded();
      expect(service.isLocked, isFalse);
    });

    test('a fresh resume without backgrounding does not re-lock', () {
      // `resumed` fires on start-up and on some transitions; it must not lock an
      // app the user never left.
      service.debugHandleLifecycle(AppLifecycleState.resumed);
      expect(service.isLocked, isFalse);
    });

    test('disabling the lock clears the locked state', () {
      service.debugHandleLifecycle(AppLifecycleState.paused);
      expect(service.isLocked, isTrue);
      service.debugSetLockEnabled(false);
      service.debugHandleLifecycle(AppLifecycleState.resumed);
      expect(service.isLocked, isFalse);
    });

    test('hidden and detached also lock the app', () {
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        service.debugReset();
        service.debugHandleLifecycle(state);
        expect(service.isLocked, isTrue, reason: '$state must lock the app');
      }
    });

    test('repeated background/resume cycles keep locking', () {
      for (var i = 0; i < 3; i++) {
        service.debugHandleLifecycle(AppLifecycleState.paused);
        expect(service.isLocked, isTrue, reason: 'cycle $i must lock');
        service.debugHandleLifecycle(AppLifecycleState.resumed);
        expect(service.isLocked, isTrue, reason: 'cycle $i must stay locked');
        service.onAuthenticationSucceeded();
        expect(service.isLocked, isFalse, reason: 'cycle $i unlocks explicitly');
      }
    });
  });
}
