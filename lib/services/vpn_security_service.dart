import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The result of one VPN check.
///
/// `unknown` and `checking` are not failures; they simply mean a definitive
/// answer is not available yet.  [detectionError] and [noNetwork] are separate
/// states so the UI can explain what happened instead of claiming a VPN was
/// found when it was not.
enum VpnSecurityStatus {
  unknown,
  checking,
  clear,
  vpnDetected,
  noNetwork,
  detectionError,
  unsupported,
}

extension VpnSecurityStatusX on VpnSecurityStatus {
  /// Weekend's fail-closed policy applies to protected content only.  A
  /// confirmed VPN, a platform error and no network all block; "unsupported"
  /// covers non-Android platforms, where this feature does not exist.
  bool get blocksProtectedContent =>
      this == VpnSecurityStatus.vpnDetected ||
      this == VpnSecurityStatus.detectionError ||
      this == VpnSecurityStatus.noNetwork;

  bool get isDefinitive =>
      this != VpnSecurityStatus.unknown && this != VpnSecurityStatus.checking;

  String get wireValue => switch (this) {
    VpnSecurityStatus.unknown => 'unknown',
    VpnSecurityStatus.checking => 'checking',
    VpnSecurityStatus.clear => 'clear',
    VpnSecurityStatus.vpnDetected => 'vpn',
    VpnSecurityStatus.noNetwork => 'no_network',
    VpnSecurityStatus.detectionError => 'error',
    VpnSecurityStatus.unsupported => 'unsupported',
  };
}

@immutable
class VpnDetectionResult {
  final VpnSecurityStatus status;
  final String? reason;
  final bool validated;
  final DateTime checkedAt;

  const VpnDetectionResult({
    required this.status,
    required this.checkedAt,
    this.reason,
    this.validated = false,
  });

  factory VpnDetectionResult.fromPlatform(
    Map<dynamic, dynamic>? raw, {
    DateTime? checkedAt,
  }) {
    final now = checkedAt ?? DateTime.now();
    if (raw == null) {
      return VpnDetectionResult(
        status: VpnSecurityStatus.detectionError,
        reason: 'empty_native_response',
        checkedAt: now,
      );
    }

    final status = switch (raw['status']) {
      'vpn' => VpnSecurityStatus.vpnDetected,
      'clear' => VpnSecurityStatus.clear,
      'no_network' => VpnSecurityStatus.noNetwork,
      'error' => VpnSecurityStatus.detectionError,
      _ => VpnSecurityStatus.detectionError,
    };

    return VpnDetectionResult(
      status: status,
      reason: raw['reason'] as String?,
      validated: raw['validated'] == true,
      checkedAt: now,
    );
  }

  static VpnDetectionResult unsupported({String? reason}) => VpnDetectionResult(
    status: VpnSecurityStatus.unsupported,
    reason: reason ?? 'platform_unsupported',
    checkedAt: DateTime.now(),
  );

  static VpnDetectionResult failure(String reason) => VpnDetectionResult(
    status: VpnSecurityStatus.detectionError,
    reason: reason,
    checkedAt: DateTime.now(),
  );
}

/// Injectable boundary so provider/route-guard tests never touch a platform
/// channel.
abstract class VpnDetectionService {
  bool get isSupported;

  Future<VpnDetectionResult> check();

  Stream<VpnDetectionResult> get changes;

  Future<void> dispose();
}

/// Android implementation backed by `ConnectivityManager` and
/// `NetworkCapabilities.TRANSPORT_VPN`.
///
/// Non-Android platforms return [VpnSecurityStatus.unsupported]: Weekend's VPN
/// policy is an Android product requirement, and failing closed on iOS/web
/// would lock users out of a feature that was never implemented there.
class PlatformVpnDetectionService implements VpnDetectionService {
  PlatformVpnDetectionService({
    MethodChannel methodChannel = const MethodChannel(_methodChannelName),
    EventChannel eventChannel = const EventChannel(_eventChannelName),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  static const _methodChannelName = 'com.weekend.app/vpn_security';
  static const _eventChannelName = 'com.weekend.app/vpn_security_events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<VpnDetectionResult> check() async {
    if (!isSupported) return VpnDetectionResult.unsupported();

    try {
      final raw = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'check',
      );
      return VpnDetectionResult.fromPlatform(raw);
    } on MissingPluginException {
      // Widget tests, or a build whose native side was stripped, cannot
      // establish state.  Treat it as unsupported rather than a VPN so tests
      // and non-Android hosts are not permanently blocked.
      return VpnDetectionResult.unsupported(reason: 'native_channel_missing');
    } on PlatformException catch (error) {
      return VpnDetectionResult.failure(error.code);
    } catch (_) {
      return VpnDetectionResult.failure('vpn_check_failed');
    }
  }

  @override
  Stream<VpnDetectionResult> get changes async* {
    if (!isSupported) return;

    try {
      await for (final event in _eventChannel.receiveBroadcastStream()) {
        if (event is Map) {
          yield VpnDetectionResult.fromPlatform(event);
        }
      }
    } on MissingPluginException {
      yield VpnDetectionResult.unsupported(
        reason: 'native_event_channel_missing',
      );
    } on PlatformException catch (error) {
      yield VpnDetectionResult.failure(error.code);
    } catch (_) {
      yield VpnDetectionResult.failure('vpn_event_stream_failed');
    }
  }

  @override
  Future<void> dispose() async {
    // The EventChannel subscription is owned by the provider and cancelled
    // there; Android unregisters its ConnectivityManager callback in onCancel.
  }
}
