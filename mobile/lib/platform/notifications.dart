import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/reminder_plan.dart';

/// Shows the service reminders as phone notifications.
abstract class ReminderNotifier {
  /// Replaces the scheduled notices for [vin] with [notices].
  Future<void> sync(String vin, List<PlannedNotice> notices);

  /// Removes every scheduled notice (reminders turned off).
  Future<void> cancelAll();
}

class NoopReminderNotifier implements ReminderNotifier {
  final synced = <String, List<PlannedNotice>>{};

  @override
  Future<void> sync(String vin, List<PlannedNotice> notices) async => synced[vin] = notices;

  @override
  Future<void> cancelAll() async => synced.clear();
}

class LocalReminderNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'service_reminders',
      'Service reminders',
      channelDescription: 'When an oil change, inspection or other service is due',
      icon: '@drawable/ic_launcher_foreground',
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<bool> _init() => _ready ??= () async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_launcher_foreground'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false; // not available (tests, unsupported platform)
    }
  }();

  Future<void> _askPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
      alert: true,
      sound: true,
    );
  }

  @override
  Future<void> sync(String vin, List<PlannedNotice> notices) async {
    if (!await _init()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final idsKey = 'notifyIds|$vin';
      for (final id in prefs.getStringList(idsKey) ?? const <String>[]) {
        await _plugin.cancel(id: int.parse(id));
      }
      if (notices.isNotEmpty) await _askPermission();
      final shown = {...prefs.getStringList('notifiedKeys') ?? const <String>[]};
      final scheduled = <String>[];
      for (final n in notices) {
        final at = n.at;
        if (at == null) {
          // Distance reminders: show once, when the mileage first shows it.
          if (shown.add(n.key)) {
            await _plugin.show(id: n.id, title: n.title, body: n.body, notificationDetails: _details);
          }
        } else {
          await _plugin.zonedSchedule(
            id: n.id,
            scheduledDate: tz.TZDateTime.from(at, tz.UTC),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: n.title,
            body: n.body,
          );
          scheduled.add('${n.id}');
        }
      }
      await prefs.setStringList(idsKey, scheduled);
      await prefs.setStringList('notifiedKeys', shown.toList());
    } catch (_) {
      // Reminders still show inside the app.
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!await _init()) return;
    try {
      await _plugin.cancelAll();
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith('notifyIds|')).toList()) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
