import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Keeps a long job (the module explorer) running with the screen off or
/// the app in the background, with its progress in a notification.
abstract class BackgroundWork {
  /// Returns whether background mode is running (false: keep the app open).
  Future<bool> start(String title, String text);
  Future<void> update(String text);
  Future<void> stop();

  /// A separate notification when the job is done (the progress one goes away).
  Future<void> announce(String title, String text);
}

class NoBackgroundWork implements BackgroundWork {
  final log = <String>[];

  bool available = true;

  @override
  Future<bool> start(String title, String text) async {
    log.add('start $title: $text');
    return available;
  }

  @override
  Future<void> update(String text) async => log.add('update $text');

  @override
  Future<void> stop() async => log.add('stop');

  @override
  Future<void> announce(String title, String text) async => log.add('announce $title: $text');
}

/// Android: a "connected device" foreground service keeps the app and its
/// Bluetooth link alive. The work itself stays in the app; the service only
/// stops Android from pausing it.
class ForegroundServiceWork implements BackgroundWork {
  bool _initialized = false;
  final _notifications = FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;

  void _init() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'long_jobs',
        channelName: 'Long jobs',
        channelDescription: 'Shows progress while the app works in the background',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
    _initialized = true;
  }

  /// Why background mode could not start, for the developer report.
  String? lastError;

  @override
  Future<bool> start(String title, String text) async {
    try {
      _init();
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      final ServiceRequestResult result;
      if (await FlutterForegroundTask.isRunningService) {
        result = await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
      } else {
        result = await FlutterForegroundTask.startService(
          serviceId: 701,
          notificationTitle: title,
          notificationText: text,
        );
      }
      if (result is ServiceRequestFailure) {
        lastError = '${result.error}';
        return false;
      }
      lastError = null;
      return await FlutterForegroundTask.isRunningService;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  @override
  Future<void> update(String text) async {
    try {
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  @override
  Future<void> announce(String title, String text) async {
    try {
      if (!_notificationsReady) {
        await _notifications.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@drawable/ic_launcher_foreground'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        );
        _notificationsReady = true;
      }
      await _notifications.show(
        id: 702,
        title: title,
        body: text,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'job_done',
            'Finished jobs',
            channelDescription: 'When a long job such as the module explorer has finished',
            icon: '@drawable/ic_launcher_foreground',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }
}
