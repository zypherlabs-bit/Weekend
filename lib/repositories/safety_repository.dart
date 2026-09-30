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

  /// Submit a report about [reportedId].
  ///
  /// Routed through the `submit_report` RPC (migration 026) rather than a
  /// direct INSERT into `reports`. The RPC is what makes a report trustworthy:
  ///
  ///   * the category is validated server-side against the schema's CHECK
  ///     constraint, so a malformed value is refused at the source;
  ///   * it is rate limited to 20 a day per reporter, so one account cannot
  ///     flood a moderator queue or get an innocent profile flagged;
  ///   * a second open report on the same person is de-duplicated instead of
  ///     stacking;
  ///   * and a non-2xx response is a hard failure, so the UI never reports a
  ///     report as received when the server did not accept it.
  ///
  /// [reason] is the free-form label shown in the report dialog. The verbatim
  /// text is always preserved in the description so moderators keep the full
  /// context, including when the label maps onto a different bucket.
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

    // Not awaited silently: a failure here must reach the caller so the user
    // is not told their report was sent when it was not.
    await client.rpc(
      'submit_report',
      params: {
        'p_reported_id': reportedId,
        'p_report_type': mapReportType(reason),
        'p_description': description,
      },
    );
  }

  /// Map the UI reason onto a `reports.report_type` value.
  ///
  /// Migration 026 extended the column's CHECK constraint with `spam`,
  /// `underage`, `unsafe_behavior` and `other`. Underage is the important one:
  /// it previously had nowhere to go and was filed as `impersonation`, so the
  /// single most urgent category in a dating app was indistinguishable from
  /// "this is a fake account" in the moderation queue. It now has its own
  /// bucket. The verbatim reason is still preserved in `description`.
  ///
  /// [reporterId] is accepted for signature stability with the direct-insert
  /// implementation this replaced; the RPC derives the reporter from the
  /// authenticated session and ignores it.
  String mapReportType(String reason) {
    final r = reason.toLowerCase();
    if (r.contains('underage') ||
        r.contains('minor') ||
        r.contains('child') ||
        r.contains('too young')) {
      return 'underage';
    }
    if (r.contains('unsafe') ||
        r.contains('threat') ||
        (r.contains('meet') && r.contains('safety'))) {
      return 'unsafe_behavior';
    }
    if (r.contains('photo')) return 'photo';
    if (r.contains('harass') || r.contains('bully')) return 'harassment';
    if (r.contains('spam')) return 'spam';
    if (r.contains('scam')) return 'scam';
    if (r.contains('impersonat') || r.contains('fake')) return 'impersonation';
    if (r.contains('message')) return 'message';
    if (r.contains('inappropriate') || r.contains('content')) {
      return 'inappropriate_content';
    }
    return 'profile';
  }
}
