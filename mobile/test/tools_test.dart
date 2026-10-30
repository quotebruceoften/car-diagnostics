import 'dart:convert';
import 'dart:io';

import 'package:cardiag_mobile/core/alerts.dart';
import 'package:cardiag_mobile/core/battery.dart';
import 'package:cardiag_mobile/core/data_backup.dart';
import 'package:cardiag_mobile/core/obd/freeze_frame.dart';
import 'package:cardiag_mobile/core/obd/pids.dart';
import 'package:cardiag_mobile/core/performance.dart';
import 'package:cardiag_mobile/core/service_log.dart';
import 'package:cardiag_mobile/core/store.dart';
import 'package:cardiag_mobile/core/trip.dart';
import 'package:cardiag_mobile/ui/settings.dart';
import 'package:cardiag_mobile/sim/vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('freeze frame', () {
    test('describes the conditions in plain language', () {
      final s = describeConditions({
        'rpm': 850,
        'speed': 0,
        'engine_load': 20,
        'coolant_temp': 35,
        'stft_b1': 12,
        'ltft_b1': 9,
      });
      expect(s.first, 'The car was standing still at idle.');
      expect(s, contains(startsWith('The engine was lightly loaded')));
      expect(s, contains(startsWith('The engine was still cold (35 °C)')));
      expect(s, contains(startsWith('Fuel trims were high (+21%)')));
      expect(describeConditions({'rpm': 3200, 'speed': 120, 'engine_load': 90}), [
        'The car was driving fast (120 km/h).',
        'The engine was working hard (90% load), e.g. accelerating or climbing.',
      ]);
      expect(describeConditions({'rpm': 0}), ['The engine was not running.']);
    });
  });

  group('alerts', () {
    test('fire once, stay on near the limit and clear with a margin', () {
      var fired = 0;
      final w = AlertWatcher(onTriggered: (_) => fired++)..rules = const [AlertRule(pid: 'coolant_temp', above: 110)];
      w.report('coolant_temp', 100, range: 170);
      expect(w.active, isEmpty);
      w.report('coolant_temp', 111, range: 170);
      w.report('coolant_temp', 112, range: 170);
      expect(fired, 1);
      expect(w.active.single.value, 112);
      w.report('coolant_temp', 109, range: 170); // within the 3.4° margin
      expect(w.isActive('coolant_temp'), isTrue);
      w.report('coolant_temp', 105, range: 170);
      expect(w.isActive('coolant_temp'), isFalse);
      w.report('coolant_temp', 115, range: 170);
      expect(fired, 2);
    });

    test('dismissed alerts hide until they clear; disabled rules never fire', () {
      final w = AlertWatcher()
        ..rules = const [
          AlertRule(pid: 'module_voltage', below: 11.8),
          AlertRule(pid: 'rpm', above: 1, enabled: false),
        ];
      w.report('module_voltage', 11.2);
      w.dismiss('module_voltage');
      expect(w.active, isEmpty);
      expect(w.isActive('module_voltage'), isTrue);
      w.report('rpm', 5000);
      expect(w.isActive('rpm'), isFalse);
    });

    test('rules round-trip through JSON', () {
      const r = AlertRule(pid: 'oil_temp', above: 130, below: 20, enabled: false);
      expect(AlertRule.fromJson(jsonDecode(jsonEncode(r.toJson()))), r);
      expect(AlertRule.fromJson('nonsense'), isNull);
    });
  });

  group('settings', () {
    test('convert alert limits back from the user\'s units', () {
      final s = AppSettings()
        ..setTemp(TempUnit.fahrenheit)
        ..setDistance(DistanceUnit.miles);
      expect(s.toPidUnit(pidsByName['coolant_temp']!, 230), closeTo(110, 0.01));
      expect(s.toPidUnit(pidsByName['speed']!, 62.1371), closeTo(100, 0.01));
      expect(s.km(100), '62.1 mi');
      expect(s.speed(100), '62 mph');
    });

    test('export and re-apply preferences', () {
      final a = AppSettings()
        ..setTemp(TempUnit.fahrenheit)
        ..setEconomy(EconomyUnit.mpgUk)
        ..setFuelPrice(1.799, '£')
        ..setAlertRules(const [AlertRule(pid: 'rpm', above: 6000)]);
      final b = AppSettings()..applyJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(b.temp, TempUnit.fahrenheit);
      expect(b.economy, EconomyUnit.mpgUk);
      expect(b.fuelPrice, 1.799);
      expect(b.money(12.5), '£12.50');
      expect(b.alertRules.single.pid, 'rpm');
    });
  });

  group('battery', () {
    test('grades resting, cranking and charging voltages', () {
      expect(gradeResting(12.6).grade, Grade.good);
      expect(gradeResting(12.3).grade, Grade.fair);
      expect(gradeResting(11.7).title, 'Flat or failing');
      expect(gradeCranking(10.4).grade, Grade.good);
      expect(gradeCranking(9.8).grade, Grade.fair);
      expect(gradeCranking(9.1).grade, Grade.bad);
      expect(gradeCharging(14.2).grade, Grade.good);
      expect(gradeCharging(12.9).grade, Grade.fair); // VW energy management
      expect(gradeCharging(12.3).title, 'Not charging');
      expect(gradeCharging(15.4).title, 'Overcharging');
    });

    test('finds the cranking dip, or none', () {
      expect(crankingMinimum([12.5, 10.3, 9.9, 11.5, 14.1], 12.5), 9.9);
      expect(crankingMinimum([12.5, 12.4, 12.5], 12.5), isNull);
      expect(crankingMinimum([], 12.5), isNull);
    });

    test('the demo battery dips while cranking, then charges', () async {
      final e = DemoEngine()..stop();
      expect(e.voltage(), closeTo(12.55, 0.05));
      e.crank();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(e.voltage(), lessThan(10.6));
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(e.voltage(), greaterThan(13.8));
    });
  });

  group('trip computer', () {
    test('integrates distance and fuel', () {
      final t0 = DateTime(2026);
      final trip = TripComputer(t0);
      // 60 km/h and 6 L/h for one minute, sampled every second.
      for (var i = 0; i <= 60; i++) {
        trip.add(t0.add(Duration(seconds: i)), 60, 6);
      }
      expect(trip.distanceKm, closeTo(1.0, 1e-6));
      expect(trip.fuelLitres, closeTo(0.1, 1e-6));
      expect(EconomyUnit.lPer100km.convert(trip.fuelLitres, trip.distanceKm), closeTo(10, 1e-6));
      expect(trip.averageSpeed, closeTo(60, 1e-6));
      final r = trip.finish(t0.add(const Duration(minutes: 1)), pricePerLitre: 2);
      expect(r.cost, closeTo(0.2, 1e-6));
      expect(TripRecord.listFromJson(jsonEncode([r.toJson()])).single.distanceKm, closeTo(1, 1e-6));
    });

    test('skips adapter dropouts', () {
      final t0 = DateTime(2026);
      final trip = TripComputer(t0)
        ..add(t0, 50, 5)
        ..add(t0.add(const Duration(seconds: 30)), 50, 5);
      expect(trip.distanceKm, 0);
    });

    test('economy units', () {
      expect(EconomyUnit.kmPerL.convert(5, 100), 20);
      expect(EconomyUnit.mpgUs.convert(10, 100), closeTo(23.52, 0.01));
      expect(EconomyUnit.mpgUk.convert(10, 100), closeTo(28.25, 0.01));
      expect(EconomyUnit.lPer100km.convert(1, 0), isNull);
      // 10 g/s of air is about 3.3 L/h of petrol.
      expect(litresPerHourFromMaf(10), closeTo(3.29, 0.01));
    });
  });

  group('service log', () {
    final now = DateTime(2026, 10, 30);
    test('reminders by date and distance, most urgent first', () {
      final log = ServiceLog(mileage: 93000)
        ..upsert(ServiceEntry(id: '1', type: ServiceType.oil, date: DateTime(2026, 3, 1), km: 80000))
        ..upsert(ServiceEntry(id: '2', type: ServiceType.inspection, date: DateTime(2024, 11, 20)))
        ..upsert(ServiceEntry(id: '3', type: ServiceType.brakeFluid, date: DateTime(2025, 6, 1)))
        ..upsert(ServiceEntry(id: '4', type: ServiceType.tyres, date: DateTime(2025, 6, 1)));
      final r = log.reminders(now);
      expect([for (final x in r) x.type], [ServiceType.inspection, ServiceType.oil, ServiceType.brakeFluid]);
      expect(r[0].status, DueStatus.soon); // 21 days left
      expect(r[1].status, DueStatus.ok);
      expect(r[1].dueKm, 95000);
      log.updateMileage(94500, now);
      expect(log.reminders(now).firstWhere((x) => x.type == ServiceType.oil).status, DueStatus.soon);
      log.updateMileage(95100, now);
      expect(log.reminders(now).first.status, DueStatus.overdue);
    });

    test('custom intervals, odometer never goes backwards, JSON round trip', () {
      final log = ServiceLog()
        ..upsert(ServiceEntry(id: '1', type: ServiceType.oil, date: DateTime(2026, 1, 15), km: 50000, cost: 89.5))
        ..intervals[ServiceType.oil] = const ServiceInterval(months: 24, km: 30000)
        ..updateMileage(52000, now)
        ..updateMileage(51000, now);
      expect(log.currentKm, 52000);
      final copy = ServiceLog.parse(log.toJsonString());
      final r = copy.reminders(now).single;
      expect(r.dueDate, DateTime(2028, 1, 15));
      expect(r.dueKm, 80000);
      expect(copy.entries.single.cost, 89.5);
      expect(ServiceLog.parse('garbage').entries, isEmpty);
    });
  });

  group('performance timer', () {
    final t0 = DateTime(2026);
    DateTime at(double s) => t0.add(Duration(microseconds: (s * 1e6).round()));

    test('0-100 km/h interpolates the start and finish', () {
      final timer = SpeedTimer(const SpeedRun(0, 100, '0–100 km/h'));
      timer.add(at(0), 0);
      expect(timer.state, TimerState.armed);
      timer.add(at(0.5), 0);
      // Constant 10 km/h per second from t=1.0; 4 samples a second.
      for (var s = 0.75; s <= 12; s += 0.25) {
        timer.add(at(s), ((s - 1.0) * 10).floorToDouble().clamp(0, 200));
        if (timer.finished) break;
      }
      expect(timer.state, TimerState.done);
      expect(timer.result!.inMilliseconds / 1000, closeTo(10.0, 0.3));
      expect(timer.distanceM, closeTo(139, 10)); // ½·a·t² with a = 2.78 m/s²
    });

    test('100-0 km/h measures braking distance', () {
      final timer = SpeedTimer(const SpeedRun(100, 0, '100–0 km/h'));
      timer.add(at(0), 110);
      expect(timer.state, TimerState.armed);
      // Braking at 36 km/h per second (10 m/s²) starting at t=1, from 110.
      for (var s = 0.2; s <= 6; s += 0.2) {
        final v = s < 1 ? 110.0 : (110 - (s - 1) * 36).clamp(0.0, 110.0);
        timer.add(at(s), v.roundToDouble());
        if (timer.finished) break;
      }
      expect(timer.state, TimerState.done);
      expect(timer.result!.inMilliseconds / 1000, closeTo(100 / 36, 0.2));
      expect(timer.distanceM, closeTo(38.6, 3)); // v²/2a
    });

    test('lifting off cancels an acceleration run', () {
      final timer = SpeedTimer(const SpeedRun(0, 100, '0–100 km/h'))
        ..add(at(0), 0)
        ..add(at(0.5), 20)
        ..add(at(1), 40)
        ..add(at(1.5), 30);
      expect(timer.state, TimerState.aborted);
    });

    test('a rolling run waits until the car is below the start speed', () {
      final timer = SpeedTimer(const SpeedRun(80, 120, '80–120 km/h'))..add(at(0), 90);
      expect(timer.state, TimerState.waiting);
      timer.add(at(1), 70);
      expect(timer.state, TimerState.armed);
      timer.add(at(2), 90);
      expect(timer.state, TimerState.running);
      expect(timer.startedAt, at(1.5));
    });
  });

  test('file store writes, lists, reads and deletes, and refuses escaping paths', () async {
    final dir = await Directory.systemTemp.createTemp('store');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileDataStore(dir);
    await store.write('trips/A.json', '[1]');
    await store.write('scan_history/A/x.json', '{}');
    expect(await store.read('trips/A.json'), '[1]');
    expect(await store.read('trips/missing.json'), isNull);
    expect(await store.list('scan_history'), ['scan_history/A/x.json']);
    expect(await store.list('nothing'), isEmpty);
    await store.delete('trips/A.json');
    expect(await store.list('trips'), isEmpty);
    expect(() => store.write('../x.json', ''), throwsArgumentError);
  });

  group('backup', () {
    test('exports every data folder and restores without deleting', () async {
      final phone = MemoryDataStore()
        ..files['service_log/VIN1.json'] = '{"entries":[]}'
        ..files['scan_history/VIN1/a.json'] = '{}'
        ..files['trips/VIN1.json'] = jsonEncode([
          {'n': 1},
        ])
        ..files['car_media/VIN1/photo.jpg'] = 'binary';
      final text = await exportData(phone, {'temp': 'fahrenheit'}, now: DateTime(2026));
      final files = (jsonDecode(text) as Map)['files'] as Map;
      expect(files.keys, unorderedEquals(['service_log/VIN1.json', 'scan_history/VIN1/a.json', 'trips/VIN1.json']));

      final newPhone = MemoryDataStore()
        ..files['trips/VIN1.json'] = jsonEncode([
          {'n': 2},
        ])
        ..files['service_log/VIN1.json'] = '{"entries":[1]}';
      final result = await importData(newPhone, text);
      expect(result.added, 1);
      expect(result.updated, 1);
      expect(result.settings['temp'], 'fahrenheit');
      expect(jsonDecode(newPhone.files['trips/VIN1.json']!), [
        {'n': 2},
        {'n': 1},
      ]);
      expect(newPhone.files['service_log/VIN1.json'], '{"entries":[1]}'); // this phone's copy wins
    });

    test('rejects other files and unsafe paths', () async {
      expect(() => importData(MemoryDataStore(), '{"a":1}'), throwsFormatException);
      expect(() => importData(MemoryDataStore(), 'not json'), throwsFormatException);
      final store = MemoryDataStore();
      await importData(
        store,
        jsonEncode({
          'format': 'car-diagnostics-backup',
          'files': {'../evil.json': 'x', 'other/x.json': 'x', 'trips/ok.json': '[]'},
        }),
      );
      expect(store.files.keys, ['trips/ok.json']);
    });
  });
}
