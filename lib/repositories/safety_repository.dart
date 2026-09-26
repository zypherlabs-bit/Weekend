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
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }

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
  ///
  /// Throws on failure: a silent no-op here used to be reported to the user as
  /// a successful unblock, so the person stayed blocked with no indication.
  Future<void> unblockUser(String blockerId, String blockedId) async {
    final client = _client;
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }
    await client
        .from('blocks')
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId);
  }

  /// The ids of the users [blockerId] has blocked, straight from the `blocks`
  /// table. Throws on failure so the UI can distinguish "you have not blocked
  /// anyone" from "the list could not be loaded".
  Future<List<String>> fetchBlockedUserIds(String blockerId) async {
    final client = _client;
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }
    final rows = await client
        .from('blocks')
        .select('blocked_id')
        .eq('blocker_id', blockerId)
        .order('created_at', ascending: false);
    return [
      for (final row in rows)
        if (row['blocked_id'] is String) row['blocked_id'] as String,
    ];
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
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }

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

  /// Map the UI reason onto the `reports.report_type` enum.
  ///
  /// The enum has no dedicated "underage" bucket, so an underage report is
  /// filed as `impersonation` — the closest category that routes to urgent
  /// review — rather than silently falling through to the generic `profile`
  /// type. The verbatim reason is always preserved in `description`.
  String _mapReportType(String reason) {
    final r = reason.toLowerCase();
    if (r.contains('underage') || r.contains('minor') || r.contains('child')) {
      return 'impersonation';
    }
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
