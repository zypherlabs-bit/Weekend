import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/vpn_security_service.dart';

@immutable
class VpnSecurityState {
  final VpnSecurityStatus status;
  final String? reason;
  final DateTime? checkedAt;
  final bool isChecking;
  final bool supported;

  /// The last protected location visited before the guard redirected to
  /// `/vpn-blocked`.  Restored once a check clears.
  final String? restoreLocation;

  const VpnSecurityState({
    required this.status,
    required this.supported,
    this.reason,
    this.checkedAt,
    this.isChecking = false,
    this.restoreLocation,
  });

  factory VpnSecurityState.initial({required bool supported}) =>
      VpnSecurityState(
        status: supported
            ? VpnSecurityStatus.unknown
            : VpnSecurityStatus.unsupported,
        supported: supported,
      );

  bool get blocksProtectedContent => status.blocksProtectedContent;

  bool get isVpnDetected => status == VpnSecurityStatus.vpnDetected;

  bool get hasDefinitiveAnswer => status.isDefinitive;

  /// Only a clear result (or a platform with no Android detector) may restore
  /// protected content.  Unknown/checking/error all keep the guard engaged.
  bool get accessConfirmed =>
      status == VpnSecurityStatus.clear ||
      status == VpnSecurityStatus.unsupported;

  /// A stable value for GoRouter's refresh notifier.  `restoreLocation` is
  /// deliberately excluded: changing it never requires a redirect by itself.
  String get routingFingerprint => '${status.wireValue}|$isChecking|$supported';

  VpnSecurityState copyWith({
    VpnSecurityStatus? status,
    bool? supported,
    String? reason,
    bool clearReason = false,
    DateTime? checkedAt,
    bool? isChecking,
    String? restoreLocation,
    bool clearRestoreLocation = false,
  }) {
    return VpnSecurityState(
      status: status ?? this.status,
      supported: supported ?? this.supported,
      reason: clearReason ? null : (reason ?? this.reason),
      checkedAt: checkedAt ?? this.checkedAt,
      isChecking: isChecking ?? this.isChecking,
      restoreLocation: clearRestoreLocation
          ? null
          : (restoreLocation ?? this.restoreLocation),
    );
  }
}

class VpnSecurityController extends StateNotifier<VpnSecurityState> {
  VpnSecurityController(this._service)
    : super(VpnSecurityState.initial(supported: _service.isSupported));

  final VpnDetectionService _service;
  StreamSubscription<VpnDetectionResult>? _subscription;
  bool _initialized = false;
  int _checkSequence = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _subscription = _service.changes.listen(
      _applyResult,
      onError: (_) =>
          _applyResult(VpnDetectionResult.failure('vpn_event_stream_failed')),
    );

    await check();
  }

  /// One-shot check used at launch, on every resume, by the retry button and
  /// before protected content is restored.  It never polls.
  Future<void> check() async {
    if (!_service.isSupported) {
      state = state.copyWith(
        status: VpnSecurityStatus.unsupported,
        supported: false,
        isChecking: false,
      );
      return;
    }
    if (state.isChecking) return;

    final sequence = ++_checkSequence;
    state = state.copyWith(isChecking: true);

    final result = await _service.check();
    if (!mounted || sequence != _checkSequence) return;
    _applyResult(result);
  }

  void _applyResult(VpnDetectionResult result) {
    if (!mounted) return;
    state = state.copyWith(
      status: result.status,
      reason: result.reason,
      clearReason: result.reason == null,
      checkedAt: result.checkedAt,
      isChecking: false,
    );
  }

  void rememberProtectedLocation(String location) {
    if (location.isEmpty || location == '/vpn-blocked') return;
    if (location == state.restoreLocation) return;
    state = state.copyWith(restoreLocation: location);
  }

  void clearRestoreLocation() {
    if (state.restoreLocation == null) return;
    state = state.copyWith(clearRestoreLocation: true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    unawaited(_service.dispose());
    super.dispose();
  }
}

/// Overridden in provider tests with a fake native detector.
final vpnDetectionServiceProvider = Provider<VpnDetectionService>(
  (ref) => PlatformVpnDetectionService(),
);

final vpnSecurityProvider =
    StateNotifierProvider<VpnSecurityController, VpnSecurityState>((ref) {
      return VpnSecurityController(ref.watch(vpnDetectionServiceProvider));
    });
