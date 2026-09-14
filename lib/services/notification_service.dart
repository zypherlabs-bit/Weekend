import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui' show Color;
import '../config/supabase_config.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Notification Channels
  static const String _matchesChannelId = 'matches_channel';

  static const String _messagesChannelId = 'messages_channel';

  static const String _plansChannelId = 'plans_channel';

  static const String _safetyChannelId = 'safety_channel';

  static const String _generalChannelId = 'general_channel';

  Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );

    _createChannels();

    _initialized = true;
  }

  void _createChannels() {
    const channels = [
      AndroidNotificationChannel(
        _matchesChannelId,
        'Matches',
        description: 'Notifications for new matches',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _messagesChannelId,
        'Messages',
        description: 'Notifications for new messages',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _plansChannelId,
        'Weekend Plans',
        description: 'Notifications for plan invitations and updates',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: false,
      ),
      AndroidNotificationChannel(
        _safetyChannelId,
        'Safety & Security',
        description: 'Important safety and security alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _generalChannelId,
        'General',
        description: 'General app notifications',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    ];
    for (final channel in channels) {
      _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    // Handle notification tap - navigate to relevant screen
    // This would typically be handled by a router or navigator key    debugPrint('Notification tapped: ${response.payload}');
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,

    required NotificationType type,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    final channelId = _getChannelId(type);

    final androidDetails = AndroidNotificationDetails(
      channelId,

      _getChannelName(type),

      channelDescription: _getChannelDescription(type),
      importance: Importance.high,

      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFFF4B72),
      colorized: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
  }

  String _getChannelId(NotificationType type) {
    switch (type) {
      case NotificationType.match:
        return _matchesChannelId;
      case NotificationType.message:
        return _messagesChannelId;
      case NotificationType.plan:
        return _plansChannelId;
      case NotificationType.safety:
        return _safetyChannelId;
      case NotificationType.general:
        return _generalChannelId;
    }
  }

  String _getChannelName(NotificationType type) {
    switch (type) {
      case NotificationType.match:
        return 'Matches';
      case NotificationType.message:
        return 'Messages';
      case NotificationType.plan:
        return 'Weekend Plans';
      case NotificationType.safety:
        return 'Safety & Security';
      case NotificationType.general:
        return 'General';
    }
  }

  String _getChannelDescription(NotificationType type) {
    switch (type) {
      case NotificationType.match:
        return 'Notifications for new matches';
      case NotificationType.message:
        return 'Notifications for new messages';
      case NotificationType.plan:
        return 'Notifications for plan invitations and updates';
      case NotificationType.safety:
        return 'Important safety and security alerts';
      case NotificationType.general:
        return 'General app notifications';
    }
  }

  Future<void> requestPermission() async {
    if (!_initialized) await initialize();

    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  // Supabase Realtime subscription for remote notifications
  RealtimeChannel? _notificationsChannel;

  Future<void> subscribeToNotifications() async {
    final client = SupabaseConfig.client;
    if (client == null) return;
    final userId = SupabaseConfig.currentUserId;
    _notificationsChannel = client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => _handleRemoteNotification(payload),
        )
        .subscribe();
  }

  void _handleRemoteNotification(PostgresChangePayload payloadData) {
    final newRecord = payloadData.newRecord;
    final typeStr = newRecord['type'] as String?;
    final title = newRecord['title'] as String? ?? 'Weekend';
    final body = newRecord['body'] as String? ?? '';
    final data = newRecord['data'] as Map<String, dynamic>?;
    NotificationType type;
    switch (typeStr) {
      case 'new_match':
        type = NotificationType.match;
        break;
      case 'new_message':
        type = NotificationType.message;
        break;
      case 'plan_invitation':
        type = NotificationType.plan;
        break;
      case 'safety_alert':
        type = NotificationType.safety;
        break;
      default:
        type = NotificationType.general;
    }
    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final notificationPayload = data?['payload'] as String?;
    showNotification(
      id: notificationId,
      title: title,
      body: body,
      type: type,
      payload: notificationPayload,
    );
  }

  void dispose() {
    _notificationsChannel?.unsubscribe();
    _initialized = false;
  }
}

enum NotificationType { match, message, plan, safety, general }
