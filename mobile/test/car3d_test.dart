import 'package:cardiag_mobile/brands/registry.dart';
import 'package:cardiag_mobile/brands/vag.dart';
import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/vin.dart';
import 'package:cardiag_mobile/main.dart';
import 'package:cardiag_mobile/ui/car3d/car_model.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model year from the VIN', () {
    expect(modelYear('WVWZZZAUZDW123456'), 2013);
    expect(modelYear('WVWZZZAUZHW123456'), 2017);
    expect(modelYear('WVWZZZ1KZ8W123456'), 2008);
    expect(modelYear('WVWZZZ1KZYW123456'), 2000);
    expect(modelYear('short'), isNull);
    // The cycle repeats every 30 years: Y is 2000 until 2029, then 2030.
    expect(modelYear('WVWZZZ1KZYW123456', currentYear: 2031), 2030);
  });

  test('VW Group VINs identify model and body style', () {
    const vag = VagBrand();
    final golf = vag.identify('WVWZZZAUZDW123456');
    expect(golf.title, 'Volkswagen Golf 7 · 2013');
    expect(golf.bodyStyle, BodyStyle.hatchback);
    expect(vag.identify('WVGZZZ5NZBW000000').bodyStyle, BodyStyle.suv);
    expect(vag.identify('WAUZZZ8K0BA000000').name, 'Audi A4');
    expect(vag.identify('TMBZZZ5E0FB000000').name, 'Škoda Octavia');
    // Unknown model code: make and year only.
    expect(vag.identify('WVWZZZZZZJW000000').name, 'Volkswagen');
    expect(genericBrand.identify('1HGCM82633A004352').name, 'Your car');
  });

  test('every module of every brand has a zone with an anchor', () {
    final mesh = buildCar(BodyStyle.hatchback, Colors.blue);
    for (final brand in [...supportedBrands, genericBrand]) {
      for (final m in brand.modules) {
        expect(mesh.anchors, contains(m.zone), reason: m.label);
      }
    }
  });

  for (final style in BodyStyle.values) {
    test('$style mesh is well formed', () {
      final mesh = buildCar(style, Colors.blue);
      final tris = [
        for (final p in mesh.parts) ...[...p.tris, ...p.decals],
      ];
      expect(tris.length, greaterThan(100));
      for (final t in tris) {
        expect(t.normal.length, closeTo(1, 1e-6));
      }
      // Body and cabin first, then the four wheels and two mirrors.
      expect(mesh.parts.where((p) => p.attached).length, 6);
      expect(mesh.anchors.keys.toSet(), CarZone.values.toSet());
    });
  }

  testWidgets('hotspots show module health after a scan and open a zone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final session = DiagSession(backupStore: MemoryBackupStore(), demoLatency: Duration.zero);
    await tester.pumpWidget(CarDiagApp(session: session));
    await tester.tap(find.text('Demo car'));
    await tester.pumpAndSettle();

    expect(find.text('Volkswagen Golf 7'), findsOneWidget);
    expect(find.text('Model year 2017'), findsOneWidget);
    expect(find.text('Engine'), findsWidgets); // grey hotspot before scanning

    await tester.tap(find.widgetWithText(FilledButton, 'Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Engine · 4'), findsOneWidget);
    expect(find.text('Chassis · 1'), findsOneWidget);
    expect(find.text('Interior'), findsOneWidget);

    await tester.tap(find.text('Engine · 4'));
    await tester.pumpAndSettle();
    expect(find.text('Engine & gearbox'), findsOneWidget);
    expect(find.text('3 faults'), findsOneWidget);
    await tester.tap(find.text('Transmission'));
    await tester.pumpAndSettle();
    expect(find.text('0CW300040H'), findsOneWidget); // module screen opened
  });

  testWidgets('paint colour can be changed', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final session = DiagSession(backupStore: MemoryBackupStore(), demoLatency: Duration.zero);
    await tester.pumpWidget(CarDiagApp(session: session));
    await tester.tap(find.text('Demo car'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paint colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GestureDetector).hitTestable().at(3));
    await tester.pumpAndSettle();
    expect(session.carPaint, isNot(carPaints.first));
  });
}
