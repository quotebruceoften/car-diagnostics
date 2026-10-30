import 'package:cardiag_mobile/core/alerts.dart';
import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/history.dart';
import 'package:cardiag_mobile/core/service_log.dart';
import 'package:cardiag_mobile/core/store.dart';
import 'package:cardiag_mobile/main.dart';
import 'package:cardiag_mobile/ui/screens/faults_tab.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DiagSession> _connect(WidgetTester tester, {DataStore? store}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final s = DiagSession(
    backupStore: MemoryBackupStore(),
    historyStore: MemoryHistoryStore(),
    dataStore: store ?? MemoryDataStore(),
    demoLatency: Duration.zero,
  );
  await tester.pumpWidget(CarDiagApp(session: s));
  await tester.tap(find.text('Demo car'));
  await tester.pumpAndSettle();
  return s;
}

Future<void> _openTool(WidgetTester tester, String name) async {
  await tester.scrollUntilVisible(find.text(name), 300, scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

/// Leaves the polling screens so no timers are pending at the end.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('a fault page shows its freeze frame in plain language', (tester) async {
    await _connect(tester);
    await tester.tap(find.text('Faults'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Saved with P0301'),
      300,
      scrollable: find.descendant(of: find.byType(FaultsTab), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Saved with P0301'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('WHEN IT HAPPENED'), 300);
    await tester.scrollUntilVisible(find.text('Engine speed'), 300);
    expect(find.textContaining('The engine was'), findsWidgets);
    await _finish(tester);
  });

  testWidgets('live alerts show a red bar, and a sensor opens its graph', (tester) async {
    final s = await _connect(tester);
    s.settings.setAlertRules(const [AlertRule(pid: 'coolant_temp', above: -30)]);
    await tester.tap(find.text('Live'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Coolant temperature'), findsWidgets);
    expect(find.textContaining('above -30 °C'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300)); // let the bar slide in
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('above -30 °C'), findsNothing);

    await tester.tap(find.text('Engine speed'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Highest'), findsOneWidget);
    expect(find.text('No alert'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('the battery test walks through rest and charging', (tester) async {
    await _connect(tester);
    await _openTool(tester, 'Battery test');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measure'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('Well charged'), findsOneWidget);
    await tester.tap(find.text('Engine already running'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Measure'));
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.textContaining('Charging normally'), findsOneWidget);
    expect(find.text('Test again'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('the trip computer starts and ends a trip', (tester) async {
    await _connect(tester);
    await _openTool(tester, 'Trip computer');
    expect(find.text('Add your fuel price'), findsOneWidget);
    await tester.tap(find.text('Start trip'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Top speed'), findsOneWidget);
    await tester.tap(find.text('End trip'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Start trip'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('the service log adds an entry and shows the next reminder', (tester) async {
    final store = MemoryDataStore();
    await _connect(tester, store: store);
    await _openTool(tester, 'Service log');
    // The demo car reports its odometer, so the mileage is filled in.
    expect(
      find.textContaining('87,654 km').evaluate().isNotEmpty || find.textContaining('87654 km').evaluate().isNotEmpty,
      isTrue,
    );
    await tester.tap(find.text('Add service'));
    await tester.pumpAndSettle();
    expect(find.text('Oil and filter change'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('COMING UP'), findsOneWidget);
    expect(find.text('Due in 12 months or in 15,000 km'), findsOneWidget);
    final saved = ServiceLog.parse(store.files['service_log/WVWZZZAUZHW123456.json']);
    expect(saved.entries.single.type, ServiceType.oil);
    expect(saved.entries.single.km, 87654);
    await _finish(tester);
  });

  testWidgets('the performance timer arms for the chosen run', (tester) async {
    await _connect(tester);
    await _openTool(tester, 'Performance');
    await tester.tap(find.widgetWithText(ChoiceChip, '0–50 km/h'));
    await tester.pump();
    await tester.tap(find.text('Get ready'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('readings/s'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Get ready'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('settings offer backup, fuel and alert options', (tester) async {
    await _connect(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Fuel economy'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Back up all data'), 300);
    expect(find.text('Restore from a backup'), findsOneWidget);
    await _finish(tester);
  });
}
