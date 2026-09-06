import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationRepository {
  Future<List<dynamic>> fetchNotifications(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      
      return response as List;
    } catch (e) {
      return [];
    }
  }

  Future<void> subscribeToNotifications(String userId) async {
    try {
      Supabase.instance.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .listen((data) {
            // Handle realtime notifications
          });
    } catch (e) {
      // ignore
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      // ignore
    }
  }
}
