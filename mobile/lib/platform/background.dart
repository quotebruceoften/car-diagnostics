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
/// shows the progress notification and stops Android from pausing the app.
///
/// This uses the notification plugin's own service, which runs no code of its
/// own. (An earlier version used a library that started a second copy of the
/// app's engine, and that copy kept cutting the Bluetooth link.)
class ForegroundServiceWork implements BackgroundWork {
  static const _id = 701;
  final _notifications = FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  bool _running = false;
  String _title = '';

  /// Why background mode could not start, for the developer report.
  String? lastError;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _ready() async {
    if (_notificationsReady) return;
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

  static const _progress = AndroidNotificationDetails(
    'long_jobs',
    'Long jobs',
    channelDescription: 'Shows progress while the app works in the background',
    icon: '@drawable/ic_launcher_foreground',
    importance: Importance.low,
    priority: Priority.low,
    onlyAlertOnce: true,
    ongoing: true,
    showWhen: false,
  );

  Future<void> _show(String text) => _android!.startForegroundService(
    id: _id,
    title: _title,
    body: text,
    notificationDetails: _progress,
    startType: AndroidServiceStartType.startNotSticky,
    foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeConnectedDevice},
  );

  @override
  Future<bool> start(String title, String text) async {
    try {
      await _ready();
      final android = _android;
      if (android == null) {
        lastError = 'only available on Android';
        return false;
      }
      if (await android.areNotificationsEnabled() != true) {
        await android.requestNotificationsPermission();
      }
      _title = title;
      await _show(text);
      _running = true;
      lastError = null;
      return true;
    } catch (e) {
      lastError = '$e';
      _running = false;
      return false;
    }
  }

  @override
  Future<void> update(String text) async {
    if (!_running) return;
    try {
      // Starting again with the same id only refreshes the notification.
      await _show(text);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    _running = false;
    try {
      await _android?.stopForegroundService();
    } catch (_) {}
  }

  @override
  Future<void> announce(String title, String text) async {
    try {
      await _ready();
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
