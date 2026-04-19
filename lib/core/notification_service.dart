import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

    // Request Android 13+ notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Request iOS notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> showFreeFallAlert() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'freefall_channel',
        'Free Fall Alert',
        channelDescription: 'Notifies when a free fall is detected',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(
      0,
      '⚠️ Free Fall Detected',
      'A free fall event was detected by the ring.',
      details,
    );
  }

  static Future<void> showSleepStartAlert() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sleep_channel',
        'Sleep Alert',
        channelDescription: 'Notifies when sleep start is detected',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(
      1,
      '수면 시작 감지',
      '수면 시작이 감지되었습니다.',
      details,
    );
  }
}
