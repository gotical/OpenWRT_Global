import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_logger.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
      );
      _initialized = true;
    } catch (e) {
      AppLogger.e('Notification init failed', e);
    }
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'openwrt_monitor',
        'OpenWRT Monitor',
        channelDescription: 'Уведомления о состоянии роутера',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (e) {
      AppLogger.e('Notification show failed', e);
    }
  }

  static Future<void> showWarning({
    required int id,
    required String title,
    required String body,
  }) async {
    await show(id: id, title: '⚠️ $title', body: body);
  }

  static Future<void> showAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await show(id: id, title: '🚨 $title', body: body);
  }
}