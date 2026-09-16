import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Data source for user-safety actions: blocking and reporting.
///
/// RLS guarantees a user can only create blocks/reports attributed to
/// themselves (`blocker_id = auth.uid()` / `reporter_id = auth.uid()`), and
/// reports are immutable once created.
class SafetyRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  /// Block [blockedId]. Blocking is idempotent: the `blocks` table has a
  /// unique (blocker_id, blocked_id) constraint.
  Future<void> blockUser(String blockerId, String blockedId) async {
    final client = _client;
    if (client == null) return;

    try {
      await client.from('blocks').insert({
        'blocker_id': blockerId,
        'blocked_id': blockedId,
      });
    } catch (e) {
      // Duplicate block is fine; surface anything else to the caller.
      if (!e.toString().contains('23505') &&
          !e.toString().contains('duplicate key')) {
        rethrow;
      }
    }
  }

  /// Remove a block the current user previously created.
  Future<void> unblockUser(String blockerId, String blockedId) async {
    final client = _client;
    if (client == null) return;

    try {
      await client
          .from('blocks')
          .delete()
          .eq('blocker_id', blockerId)
          .eq('blocked_id', blockedId);
    } catch (e) {
      // Best-effort: unblocking failure should not crash the UI.
    }
  }

  /// Submit a report about [reportedId]. Reports are write-once from the
  /// client; only moderators can act on them afterwards.
  ///
  /// [reason] is the free-form label shown in the report dialog; it is mapped
  /// to the `report_type` enum enforced by the schema and stored verbatim in
  /// `description` so moderators keep the full context.
  Future<void> reportUser(
    String reporterId,
    String reportedId,
    String reason, {
    String? details,
  }) async {
    final client = _client;
    if (client == null) return;

    final description = details == null || details.isEmpty
        ? reason
        : '$reason — $details';

    await client.from('reports').insert({
      'reporter_id': reporterId,
      'reported_id': reportedId,
      'report_type': _mapReportType(reason),
      'description': description,
      'status': 'pending',
    });
  }

  String _mapReportType(String reason) {
    final r = reason.toLowerCase();
    if (r.contains('photo')) return 'photo';
    if (r.contains('harass') || r.contains('bully')) return 'harassment';
    if (r.contains('spam') || r.contains('scam')) return 'scam';
    if (r.contains('impersonat') || r.contains('fake')) return 'impersonation';
    if (r.contains('message')) return 'message';
    if (r.contains('inappropriate') || r.contains('content')) {
      return 'inappropriate_content';
    }
    return 'profile';
  }
}
