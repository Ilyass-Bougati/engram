import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminders.dart';

/// The phone's notifications, through flutter_local_notifications.
class LocalNotificationScheduler implements NotificationScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _icon = '@drawable/ic_stat_engram';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'study_reminders',
      'Study reminders',
      channelDescription: 'A nudge at the times you choose in Settings.',
      icon: _icon,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> initialize() => _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings(_icon),
      // Permission is asked for when reminders are turned on, not at launch.
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      ),
    ),
  );

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // Before Android 13 there's nothing to ask: null means allowed.
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> schedule(
    int id,
    tz.TZDateTime when, {
    required String title,
    required String body,
  }) => _plugin.zonedSchedule(
    id: id,
    scheduledDate: when,
    notificationDetails: _details,
    // A few minutes' leeway is fine for a reminder, and needs no exact-alarm permission.
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    title: title,
    body: body,
  );
}
