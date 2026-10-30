import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/obd/pids.dart';
import 'package:cardiag_mobile/main.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:cardiag_mobile/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('settings persist across app launches', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await AppSettings.load();
    first
      ..setThemeMode(ThemeMode.dark)
      ..setTemp(TempUnit.fahrenheit)
      ..setDistance(DistanceUnit.miles)
      ..setAutoReconnect(false)
      ..setLastAdapter(const SavedAdapter.ble(id: 'AA:BB', name: 'IOS-Vlink'));
    await Future<void>.delayed(Duration.zero);

    final second = await AppSettings.load();
    expect(second.themeMode, ThemeMode.dark);
    expect(second.temp, TempUnit.fahrenheit);
    expect(second.distance, DistanceUnit.miles);
    expect(second.autoReconnect, isFalse);
    expect(second.lastAdapter!.name, 'IOS-Vlink');
    expect(second.lastAdapter!.isBle, isTrue);

    second.setLastAdapter(const SavedAdapter.wifi(host: '192.168.0.10', port: 35000));
    await Future<void>.delayed(Duration.zero);
    final third = await AppSettings.load();
    expect(third.lastAdapter!.detail, '192.168.0.10:35000');
  });

  test('unit conversion', () {
    final s = AppSettings();
    expect(s.format(lookupPid('coolant_temp'), 90), '90 °C');
    expect(s.format(lookupPid('rpm'), 1730.0), '1730 rpm');
    s
      ..setTemp(TempUnit.fahrenheit)
      ..setDistance(DistanceUnit.miles);
    expect(s.format(lookupPid('coolant_temp'), 90), '194 °F');
    expect(s.format(lookupPid('speed'), 100), '62.1 mph');
    expect(s.format(lookupPid('distance_since_clear'), 1234), '767 mi');
    expect(s.format(lookupPid('module_voltage'), 14.1), '14.1 V');
    expect(s.range(lookupPid('coolant_temp')), (-40.0, 266.0));
  });

  Future<void> pump(WidgetTester tester, DiagSession session) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CarDiagApp(session: session));
    await tester.pumpAndSettle();
  }

  testWidgets('overview shows the chosen units', (tester) async {
    final settings = AppSettings()
      ..setTemp(TempUnit.fahrenheit)
      ..setDistance(DistanceUnit.miles);
    final session = DiagSession(settings: settings, backupStore: MemoryBackupStore(), demoLatency: Duration.zero);
    await pump(tester, session);
    await tester.tap(find.text('Demo car'));
    await tester.pumpAndSettle();
    expect(find.textContaining('°F'), findsWidgets);
    expect(find.text('767 mi'), findsOneWidget); // 1234 km since codes were cleared
  });

  testWidgets('saved adapter is offered on the connect screen', (tester) async {
    final settings = AppSettings()
      ..setAutoReconnect(false)
      ..setLastAdapter(const SavedAdapter.wifi(host: '192.168.0.10', port: 35000));
    await pump(tester, DiagSession(settings: settings));
    expect(find.text('YOUR ADAPTER'), findsOneWidget);
    expect(find.text('192.168.0.10:35000'), findsOneWidget);
    expect(find.text('OTHER WAYS TO CONNECT'), findsOneWidget);
  });

  testWidgets('settings screen changes the theme', (tester) async {
    final session = DiagSession();
    await pump(tester, session);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(session.settings.themeMode, ThemeMode.dark);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
  });
}
