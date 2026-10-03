import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui' show Color;
import '../config/supabase_config.dart';

// Firebase imports — used when a Firebase project is configured.
// The app works without Firebase (foreground notifications via Realtime);
// FCM adds background and closed-app delivery.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _initialized = false;
  bool _firebaseInitialized = false;

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

    // Initialize Firebase + FCM (optional — app works without it).
    _initFirebase();

    _initialized = true;
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseInitialized = true;

      // Request FCM permissions.
      await _messaging.requestPermission();

      // Configure foreground message handling.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpenedApp);

      // Get and store the FCM token for this user.
      _saveDeviceToken();

      debugPrint('FCM initialized successfully');
    } catch (e) {
      debugPrint('FCM not configured (using local notifications only): $e');
    }
  }

  /// Saves the current FCM token to the device_tokens table so the backend
  /// can send push notifications via FCM.
  Future<void> _saveDeviceToken() async {
    if (!_firebaseInitialized) return;

    final client = SupabaseConfig.client;
    if (client == null) return;
    final userId = SupabaseConfig.currentUserId;
    if (userId.isEmpty || userId == 'unauthenticated' || userId == 'me') return;

    final token = await _messaging.getToken();
    if (token == null) return;

    final deviceId = await _getOrCreateDeviceId();
    if (deviceId == null) return;

    try {
      await client.from('device_tokens').upsert({
        'user_id': userId,
        'device_id': deviceId,
        'token': token,
        'platform': 'android',
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, device_id');
    } catch (e) {
      debugPrint('Failed to save FCM registration: $e');
    }
  }

  static String? _persistentDeviceId;
  String? get _deviceId => _persistentDeviceId;

  Future<String?> _getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId;

    // simple approach: use the FCM token hash as a stable device id
    final token = await _messaging.getToken();
    if (token == null) return null;
    _persistentDeviceId = token.substring(0, 32);
    return _persistentDeviceId;
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final typeStr = message.data['type'] as String?;
    final type = _typeFromString(typeStr);

    showNotification(
      id: notification.hashCode,
      title: notification.title ?? 'Weekend',
      body: notification.body ?? '',
      type: type,
      payload: message.data['payload'] as String?,
    );
  }

  void _onNotificationOpenedApp(RemoteMessage message) {
    debugPrint('Notification opened app: ${message.messageId}');
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
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

  NotificationType _typeFromString(String? typeStr) {
    switch (typeStr) {
      case 'new_match':
        return NotificationType.match;
      case 'new_message':
        return NotificationType.message;
      case 'plan_invitation':
        return NotificationType.plan;
      case 'safety_alert':
        return NotificationType.safety;
      default:
        return NotificationType.general;
    }
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

    // FCM permission
    if (_firebaseInitialized) {
      await _messaging.requestPermission();
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  // Supabase Realtime subscription for foreground notifications
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
    final type = _typeFromString(typeStr);
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

/// Background handler for FCM messages when the app is not in the foreground.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling a background message: ${message.messageId}');
}
