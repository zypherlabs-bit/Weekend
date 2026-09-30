import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/models.dart';

/// Data source for the notification centre.
///
/// This class previously existed but was called from nowhere in `lib/`, so the
/// two notification types the database produced (`new_match`, `new_message`)
/// only ever existed as a transient system toast raised by `NotificationService`
/// and then vanished. It also leaked: `subscribeToNotifications` attached a
/// `.listen()` that was never stored and never cancelled, and whose body was an
/// empty comment.
///
/// Reads now go through the migration 026 RPCs, which is what makes the
/// unread count and mark-all-read possible without the client having to page
/// the entire table to count it.
class NotificationRepository {
  SupabaseClient? get _client => SupabaseConfig.client;

  StreamSubscription<List<dynamic>>? _subscription;

  /// One page of notifications, newest first.
  ///
  /// Throws on failure. The previous implementation returned an empty list on
  /// error, which made "your notifications could not load" indistinguishable
  /// from "you have no notifications" - and the notification centre is exactly
  /// the screen where that difference matters.
  Future<List<AppNotification>> fetchNotifications({
    int limit = 50,
    int offset = 0,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError(SupabaseConfig.configError);
    }

    final result = await client.rpc(
      'get_notifications',
      params: {'p_limit': limit, 'p_offset': offset},
    );

    return [
      for (final row in result as List)
        AppNotification.fromRow(Map<String, dynamic>.from(row as Map)),
    ];
  }

  /// How many notifications are unread. Drives the tab badge, so it has to be
  /// cheap - this is a COUNT against the `(user_id, is_read, created_at)`
  /// index added in migration 026, not a full table read.
  Future<int> unreadCount() async {
    final client = _client;
    if (client == null) return 0;

    final result = await client.rpc('notification_unread_count');
    return result is int ? result : 0;
  }

  Future<void> markAsRead(String notificationId) async {
    final client = _client;
    if (client == null) return;

    await client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Mark every unread notification as read. Returns how many were updated.
  ///
  /// A failure here is swallowed deliberately: "mark all read" is a
  /// convenience, and failing it should not interrupt whatever the user was
  /// actually doing. Individual failures re-throw, because leaving one item
  /// visibly unread would look like data loss.
  Future<int> markAllAsRead() async {
    final client = _client;
    if (client == null) return 0;

    try {
      final result = await client.rpc('mark_all_notifications_read');
      return result is int ? result : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Stream inserts to this user's notifications.
  ///
  /// The previous implementation attached a listener and dropped the handle on
  /// the floor, so it could never be cancelled and every call added another
  /// permanent listener. The subscription is held here and released by
  /// [cancelSubscription], which the caller must invoke when it tears down.
  void subscribeToNotifications(
    String userId, {
    void Function(AppNotification notification)? onNew,
  }) {
    final client = _client;
    if (client == null) return;

    cancelSubscription();

    _subscription = client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen(
          (data) {
            // postgres_changes streams deliver INSERT/UPDATE/DELETE. Only an
            // insert is a new notification; re-emitting an update would
            // duplicate an item the list already holds.
            for (final event in data) {
              if (event['event_type'] != 'INSERT') continue;
              final row = event['new'];
              if (row is! Map) continue;
              onNew?.call(
                AppNotification.fromRow(Map<String, dynamic>.from(row)),
              );
            }
          },
          // A dropped realtime connection is not an error the user needs to see;
          // the initial page load already returned real data.
          onError: (_) {},
        );
  }

  Future<void> cancelSubscription() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}