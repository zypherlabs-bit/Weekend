import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';
import '../repositories/discovery_repository.dart';

/// Aggregated Swipe Surge state for the viewer's own city.
///
/// The value is always the server's answer; there is no client-side
/// simulation of a surge. When no backend is configured the state stays
/// inactive so the banner never fabricates an active event.
class SurgeNotifier extends StateNotifier<SurgeState> {
  SurgeNotifier() : super(const SurgeState(active: false));

  final DiscoveryRepository _discoveryRepo = DiscoveryRepository();

  /// Fetch fresh state from the server (no-op without a backend).
  Future<void> refresh() async {
    if (SupabaseConfig.currentUserId.isEmpty) return;
    try {
      state = await _discoveryRepo.getSurgeState();
    } catch (e) {
      debugPrint('Surge refresh failed: $e');
    }
  }
}

final surgeProvider =
    StateNotifierProvider<SurgeNotifier, SurgeState>((ref) => SurgeNotifier());
