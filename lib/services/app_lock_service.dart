import 'package:flutter/widgets.dart';

import 'biometric_auth_service.dart';
import 'secure_storage_service.dart';

/// Lifecycle-aware application lock.
///
/// Why the previous implementation never re-locked the app
/// ---------------------------------------------------
/// The old design hung an [OverlayEntry] off `Overlay.of(context)` from the
/// state of the widget that BUILDS `MaterialApp.router`. That widget sits
/// ABOVE the MaterialApp, so at the moment the overlay was inserted there was
/// no Overlay in the tree to insert into - the call throws and the lock screen
/// never appears. Because the throw happened inside an async gap it was
/// swallowed, which is why the failure looked like "the fingerprint prompt
/// does not appear" rather than a crash.
///
/// The second defect was treating `AppLifecycleState.inactive` as "the user
/// left". `inactive` is also emitted every time a system UI surface comes to
/// the front - including Android's own BiometricPrompt and Credential Manager
/// sheet. Treating it as background both (a) re-armed the lock while the
/// prompt was on screen and (b) let an `inactive` -> `resumed` pair unlock the
/// app without any authentication at all.
///
/// This class fixes both: it is a pure state machine with no dependency on the
/// widget tree, it distinguishes "really backgrounded" from "a system surface
/// opened", and it never unlocks itself - unlocking is driven only by a
/// successful [BiometricAuthService.authenticate].
class AppLockService with WidgetsBindingObserver {
  AppLockService._();

  static final AppLockService instance = AppLockService._();

  /// How long the app may stay backgrounded before returning re-locks it.
  ///
  /// A short grace period avoids demanding a fingerprint for a notification
  /// shade pull. Set to [Duration.zero] to lock on every resume.
  static const Duration gracePeriod = Duration(seconds: 0);

  final ValueNotifier<bool> locked = ValueNotifier<bool>(false);

  bool _lockEnabled = false;
  bool _backgrounded = false;
  DateTime? _backgroundedAt;
  bool _observerAttached = false;

  /// True when the user has turned the app lock on.
  bool get isLockEnabled => _lockEnabled;

  /// True when the UI must be covered right now.
  bool get isLocked => locked.value;

  /// Attach the observer. Safe to call more than once.
  void attach() {
    if (_observerAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _observerAttached = true;
  }

  void detach() {
    if (!_observerAttached) return;
    WidgetsBinding.instance.removeObserver(this);
    _observerAttached = false;
  }

  /// Load the persisted preference and apply it to the current state.
  ///
  /// Called once at start-up. Turning the lock off while the app is locked
  /// clears the lock immediately, which is what the "Disable app lock" action
  /// on the lock screen does.
  Future<void> loadFromStorage() async {
    try {
      _lockEnabled = await SecureStorageService.isBiometricEnabled();
    } catch (e) {
      // A keystore read failure must not leave the app in a permanently locked
      // state with no way out, nor silently disable the lock. Default to the
      // safe option - locked - and let the user authenticate.
      debugPrint('App lock preference unreadable: $e');
      _lockEnabled = true;
    }
    if (!_lockEnabled && locked.value) {
      locked.value = false;
    }
  }

  /// Turn the app lock on/off. The caller is responsible for having
  /// authenticated the user first (see `SettingsDialog`).
  Future<void> setLockEnabled(bool enabled) async {
    _lockEnabled = enabled;
    await SecureStorageService.setBiometricEnabled(enabled);
    if (!enabled) locked.value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handleResumed();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // A REAL backgrounding: the whole activity is being stopped.
        _handleBackgrounded();
        break;

      case AppLifecycleState.inactive:
        // NOT a backgrounding. This fires when a system surface (BiometricPrompt,
        // Credential Manager, share sheet, notification shade) takes focus while
        // the Flutter activity is still alive. Recording a lock here is what
        // caused the old "unlock prompt never appears" / "app unlocks itself"
        // behaviour, so it is deliberately ignored.
        break;
    }
  }

  void _handleBackgrounded() {
    if (!_lockEnabled) return;
    if (_backgrounded) return;
    _backgrounded = true;
    _backgroundedAt = DateTime.now();
    // Lock immediately. Re-hiding a profile the user could otherwise return to
    // with no prompt is precisely the threat the app lock exists to stop.
    locked.value = true;
  }

  void _handleResumed() {
    if (!_lockEnabled) {
      locked.value = false;
      return;
    }
    if (!_backgrounded) return; // never actually left
    _backgrounded = false;
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) return;
    final away = DateTime.now().difference(since);
    locked.value = away >= gracePeriod;
  }

  /// Called ONLY after a successful biometric/device-credential prompt.
  ///
  /// There is deliberately no timeout, no "assume unlocked" branch and no
  /// boolean stored on disk: the only path to an unlocked app is a real
  /// authentication result.
  void onAuthenticationSucceeded() {
    locked.value = false;
    _backgrounded = false;
    _backgroundedAt = null;
  }

  /// Test seam: drive the state machine without the binding.
  @visibleForTesting
  void debugHandleLifecycle(AppLifecycleState state) =>
      didChangeAppLifecycleState(state);

  @visibleForTesting
  void debugSetLockEnabled(bool value) => _lockEnabled = value;

  @visibleForTesting
  void debugReset() {
    _backgrounded = false;
    _backgroundedAt = null;
    locked.value = false;
  }
}
