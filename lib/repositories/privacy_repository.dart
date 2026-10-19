import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Client surface for the privacy & availability features backed by
/// migration 031's server RPCs. Every call is enforced server-side
/// (entitlements, provenance, expiry); the repository only reports what the
/// server actually did and never fakes a success.
class PrivacyRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Toggle Incognito (profile discoverable only by people already liked)
  /// or Snooze (temporarily removed from discovery). Sends/likes/matches
  /// are never touched by either mode.
  ///
  /// Returns true when the server acknowledged the toggle.
  Future<bool> setPrivacyMode(
    String mode, {
    required bool enabled,
    int? snoozeHours,
  }) async {
    final client = _client;
    if (client == null) return false;

    try {
      final result = await client.rpc('set_privacy_mode', params: {
        'p_mode': mode,
        'p_enabled': enabled,
        'p_snooze_hours': snoozeHours,
      });
      return result is Map && result['mode'] == mode;
    } catch (_) {
      return false;
    }
  }

  /// Set or clear the Away status (an optional break message that existing
  /// connections may see while it is active).
  ///
  /// Pass `null`/[emptyString] to clear. Returns the persisted message, or
  /// null when the server rejected it (too long, disallowed content).
  Future<String?> setAwayStatus(String? message, {int hours = 24}) async {
    final client = _client;
    if (client == null) return null;

    try {
      final result = await client.rpc('set_away_status', params: {
        'p_message': message,
        'p_hours': hours,
      });
      if (result is Map && result['away'] == true) {
        return result['message'] as String? ?? '';
      }
      if (result is Map && result['away'] == false) return '';
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Configure Travel Mode. This stores a user-chosen approximate
  /// destination in their own settings; the real GPS location is never
  /// rewritten, and the destination auto-expires after 7 days on the
  /// server. Pass an empty/null city to disable.
  Future<bool> setTravelLocation({
    String? city,
    double? latitude,
    double? longitude,
  }) async {
    final client = _client;
    if (client == null) return false;

    try {
      final result = await client.rpc('set_travel_location', params: {
        'p_city': city,
        'p_lat': latitude,
        'p_lon': longitude,
      });
      if (result is Map) {
        return result['travel_enabled'] == true ||
            ((city == null || city.trim().isEmpty) &&
                result['travel_enabled'] == false);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Away status of the OTHER member of a conversation, as the server sees
  /// it right now (`get_conversation_away_note`, migration 031). The chat
  /// screen refreshes with this on entry because `MatchItem.awayMessage`
  /// is only as fresh as the last matches fetch.
  ///
  /// Returns the record only when the server answered; a null means the
  /// call failed and the stale value must remain authoritative.
  Future<({bool away, String message})?> fetchConversationAwayNote(
    String conversationId,
  ) async {
    final client = _client;
    if (client == null || conversationId.isEmpty) return null;

    try {
      final result = await client.rpc(
        'get_conversation_away_note',
        params: {'p_conversation_id': conversationId},
      );
      if (result is Map) {
        return (
          away: result['away'] == true,
          message: result['message'] as String? ?? '',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Toggle the Online Now consent (`user_settings.show_online_now`).
  ///
  /// Discovery consults this column with a safe default (`true`). The
  /// write is the same owner-row upsert the push-notification setting uses,
  /// so a stored toggle survives restarts and re-reads honestly.
  Future<bool> setShowOnlineNow(bool value) async {
    final client = _client;
    if (client == null) return false;
    final me = SupabaseConfig.currentUserId;
    if (me.isEmpty) return false;
    try {
      await client.from('user_settings').upsert({
        'user_id': me,
        'show_online_now': value,
      }, onConflict: 'user_id');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Read the caller's persisted travel configuration through RLS
  /// (`user_settings` owner-row read).
  Future<Map<String, dynamic>?> fetchTravelConfig() async {
    final client = _client;
    if (client == null) return null;
    try {
      final me = SupabaseConfig.currentUserId;
      if (me.isEmpty) return null;
      final row = await client
          .from('user_settings')
          .select(
              'travel_mode_enabled, travel_city, travel_lat, travel_lon, travel_started_at')
          .eq('user_id', me)
          .maybeSingle();
      return row;
    } catch (_) {
      return null;
    }
  }

  /// Read the caller's persisted privacy toggles.
  Future<Map<String, dynamic>?> fetchPrivacyToggles() async {
    final client = _client;
    if (client == null) return null;
    try {
      final me = SupabaseConfig.currentUserId;
      if (me.isEmpty) return null;
      final row = await client
          .from('user_settings')
          .select(
              'incognito_mode, snooze_mode, snooze_until, show_online_now')
          .eq('user_id', me)
          .maybeSingle();
      return row;
    } catch (_) {
      return null;
    }
  }
}
