import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/reminder_plan.dart';
import 'package:cardiag_mobile/core/service_log.dart';
import 'package:cardiag_mobile/core/store.dart';
import 'package:cardiag_mobile/platform/notifications.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:cardiag_mobile/ui/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 30, 12);

  test('date reminders are scheduled a week before and on the day', () {
    final log = ServiceLog()..upsert(ServiceEntry(id: '1', type: ServiceType.inspection, date: DateTime(2024, 12, 2)));
    final notices = planServiceNotices('VIN', 'Golf 7', log, now);
    expect([for (final n in notices) n.at], [DateTime(2026, 11, 25, 10), DateTime(2026, 12, 2, 10)]);
    expect(notices.first.title, 'Inspection due in a week');
    expect(notices.last.body, 'Golf 7: the inspection is due today.');
  });

  test('past dates are not scheduled', () {
    final log = ServiceLog()..upsert(ServiceEntry(id: '1', type: ServiceType.brakeFluid, date: DateTime(2024, 10, 1)));
    expect(planServiceNotices('VIN', 'Golf', log, now), isEmpty);
  });

  test('distance reminders show straight away once close', () {
    final log = ServiceLog(mileage: 88700)
      ..upsert(ServiceEntry(id: '1', type: ServiceType.oil, date: DateTime(2026, 9, 1), km: 74100));
    final km = planServiceNotices('VIN', 'Golf', log, now).where((n) => n.at == null).single;
    expect(km.title, 'Oil and filter change due soon');
    expect(km.body, 'Golf: due at 89100 km, 400 km from now.');
    log.updateMileage(89300, now);
    final over = planServiceNotices('VIN', 'Golf', log, now).where((n) => n.at == null).single;
    expect(over.title, 'Oil and filter change overdue');
    expect(over.key, isNot(km.key)); // a new notice, not a repeat
  });

  test('notice ids are stable and positive', () {
    const n = PlannedNotice(key: 'date|VIN|oil|2027-03-01|due', title: '', body: '');
    expect(n.id, const PlannedNotice(key: 'date|VIN|oil|2027-03-01|due', title: 'x', body: 'y').id);
    expect(n.id, greaterThan(0));
    expect(n.id, isNot(const PlannedNotice(key: 'date|VIN|oil|2027-03-01|week', title: '', body: '').id));
  });

  test('saving the service log updates the notifications, unless turned off', () async {
    final notifier = NoopReminderNotifier();
    final settings = AppSettings();
    final session = DiagSession(
      settings: settings,
      backupStore: MemoryBackupStore(),
      dataStore: MemoryDataStore(),
      notifier: notifier,
    );
    final log = ServiceLog()..upsert(ServiceEntry(id: '1', type: ServiceType.oil, date: DateTime.now(), km: 50000));
    await session.saveServiceLog('WVWZZZAUZDW000001', log);
    await Future<void>.delayed(Duration.zero);
    expect(notifier.synced['WVWZZZAUZDW000001'], hasLength(2));

    settings.setServiceNotifications(false);
    await session.syncServiceNotifications('WVWZZZAUZDW000001');
    expect(notifier.synced['WVWZZZAUZDW000001'], isEmpty);
  });
}
