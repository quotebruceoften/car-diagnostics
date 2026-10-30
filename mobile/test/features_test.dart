import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/obd/dtc_info.dart';
import 'package:cardiag_mobile/core/obd/readiness.dart';
import 'package:cardiag_mobile/core/obd/pids.dart';
import 'package:cardiag_mobile/main.dart';
import 'package:cardiag_mobile/ui/screens/dashboard_screen.dart';
import 'package:cardiag_mobile/ui/settings.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DiagSession> connectDemo(WidgetTester tester, {DiagSession? session}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final s = session ?? DiagSession(backupStore: MemoryBackupStore(), demoLatency: Duration.zero);
  await tester.pumpWidget(CarDiagApp(session: s));
  await tester.tap(find.text('Demo car'));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  readinessTests();
  dashboardTests();
  group('fault code explanations', () {
    test('known codes have specific entries', () {
      final misfire = dtcInfo('P0302');
      expect(misfire.title, 'Cylinder 2 misfires');
      expect(misfire.severity, Severity.high);
      expect(misfire.causes, isNotEmpty);
      expect(misfire.isGeneric, isFalse);
      expect(dtcInfo('P0217').severity, Severity.critical);
      expect(dtcInfo('p0442').severity, Severity.low); // case-insensitive
    });

    test('unknown codes are explained from their structure', () {
      final p = dtcInfo('P0399');
      expect(p.isGeneric, isTrue);
      expect(p.meaning, contains('ignition and misfire'));
      expect(dtcInfo('P1234').meaning, contains('manufacturer-specific'));
      expect(dtcInfo('C1234').title, 'Chassis fault');
      expect(dtcInfo('B0001').title, 'Body electronics fault');
      expect(dtcInfo('U0402').title, 'Network communication fault');
      expect(dtcInfo('X').title, 'Unknown fault');
    });
  });

  testWidgets('tapping a fault code opens its explanation', (tester) async {
    await connectDemo(tester);
    await tester.tap(find.text('Faults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('P0301'));
    await tester.pumpAndSettle();
    expect(find.text('Cylinder 1 misfires'), findsOneWidget);
    expect(find.text('Serious'), findsOneWidget);
    expect(find.text('Worn spark plugs'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Search "P0301 Volkswagen Golf 7"'), 300);
    expect(find.textContaining('Search "P0301 Volkswagen Golf 7"'), findsOneWidget);
  });
}

void readinessTests() {
  group('readiness', () {
    test('decodes petrol monitors', () {
      // MIL off, 0 codes; misfire/fuel/components available and complete;
      // catalyst, EVAP, O2 sensor, O2 heater available; EVAP incomplete.
      final r = decodeReadiness([0x00, 0x07, 0x65, 0x04]);
      expect(r.diesel, isFalse);
      expect(r.monitors.map((m) => m.name), [
        'Misfire',
        'Fuel system',
        'Components',
        'Catalytic converter',
        'Fuel vapour (EVAP) system',
        'Oxygen sensors',
        'Oxygen sensor heaters',
      ]);
      expect(r.incomplete.single.name, 'Fuel vapour (EVAP) system');
      expect(r.verdict, ReadinessVerdict.almostReady);
    });

    test('decodes diesel monitors and continuous incompletes', () {
      // Diesel (bit 3), fuel system incomplete (bit 5); PM filter + NOx available, PM filter incomplete.
      final r = decodeReadiness([0x00, 0x2F, 0x42, 0x40]);
      expect(r.diesel, isTrue);
      expect(r.monitors.map((m) => m.name), containsAll(['Particulate filter', 'NOx / SCR aftertreatment']));
      expect(r.incomplete.map((m) => m.name), ['Fuel system', 'Particulate filter']);
      expect(r.verdict, ReadinessVerdict.notReady);
    });

    test('check engine light means not ready', () {
      expect(decodeReadiness([0x82, 0x07, 0x65, 0x00]).verdict, ReadinessVerdict.notReady);
      expect(decodeReadiness([0x00, 0x07, 0x65, 0x00]).verdict, ReadinessVerdict.ready);
    });
  });

  testWidgets('readiness screen, and clearing codes resets the self-tests', (tester) async {
    final session = await connectDemo(tester);
    expect(find.textContaining('Inspection: Not ready'), findsOneWidget); // MIL is on in the demo
    await tester.tap(find.textContaining('Inspection:'));
    await tester.pumpAndSettle();
    expect(find.text('Catalytic converter'), findsOneWidget);
    expect(find.text('Not finished'), findsNothing);

    await tester.runAsync(() => session.obd.clearDtcs());
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Inspection:'));
    await tester.pumpAndSettle();
    expect(find.text('Not ready yet'), findsOneWidget);
    expect(find.text('Not finished'), findsNWidgets(3));
  });
}

void dashboardTests() {
  test('drive recording CSV uses the chosen units', () {
    final settings = AppSettings()..setDistance(DistanceUnit.miles);
    final csv = buildDriveCsv(
      [lookupPid('rpm'), lookupPid('speed')],
      [
        (DateTime.utc(2026, 10, 30, 9), [850.0, 0]),
        (DateTime.utc(2026, 10, 30, 9, 0, 1), [2100.5, settings.convert(lookupPid('speed'), 100).$1]),
        (DateTime.utc(2026, 10, 30, 9, 0, 2), [null, 62]),
      ],
      settings,
    );
    expect(csv.split('\n'), [
      'time,rpm (rpm),speed (mph)',
      '2026-10-30T09:00:00.000Z,850,0',
      '2026-10-30T09:00:01.000Z,2101,62.1',
      '2026-10-30T09:00:02.000Z,,62',
      '',
    ]);
  });

  testWidgets('driving dashboard shows live dials', (tester) async {
    await connectDemo(tester);
    tester.view.physicalSize = const Size(2400, 1080); // phones turn sideways for the dashboard
    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Driving dashboard'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Engine speed'), findsOneWidget);
    expect(find.text('Vehicle speed'), findsOneWidget);
    expect(find.text('rpm'), findsOneWidget);
    expect(find.text('Record drive'), findsOneWidget);
    await tester.tap(find.text('Record drive'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('REC'), findsOneWidget);
    await tester.tap(find.byTooltip('Close dashboard'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Driving dashboard'), findsOneWidget);
    // Stop the polling loops and let their last timers run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
