import 'dart:io';

import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/history.dart';
import 'package:cardiag_mobile/core/uds/uds_client.dart';
import 'package:cardiag_mobile/main.dart';
import 'package:cardiag_mobile/ui/report_pdf.dart';
import 'package:cardiag_mobile/ui/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScanRecord _record(DateTime t, List<(String, String)> faults) => ScanRecord(
  timestamp: t,
  vin: 'WVWZZZAUZDW123456',
  carName: 'Volkswagen Golf 7 · 2013',
  modules: [
    ModuleRecord(
      address: '01',
      name: 'Engine',
      partNumber: '04E906016DE',
      faults: [
        for (final (code, desc) in faults) FaultRecord(code: code, display: code, description: desc, active: true),
      ],
    ),
    const ModuleRecord(address: '17', name: 'Instrument cluster', faults: []),
  ],
);

void main() {
  test('history store keeps scans per car, newest first', () async {
    final dir = await Directory.systemTemp.createTemp('hist');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileHistoryStore(dir);
    final older = _record(DateTime.utc(2026, 10, 1), [('P0301', 'Cylinder 1 misfire detected')]);
    final newer = _record(DateTime.utc(2026, 10, 20), [('P0420', 'Catalyst efficiency below threshold')]);
    await store.save(older);
    await store.save(newer);
    final list = await store.list('WVWZZZAUZDW123456');
    expect(list.map((r) => r.timestamp), [newer.timestamp, older.timestamp]);
    expect(list.first.modules.first.faults.single.code, 'P0420');
    expect(await store.list('OTHERVIN'), isEmpty);

    final cmp = ScanComparison(list[0], list[1]);
    expect(cmp.added.single.$2.code, 'P0420');
    expect(cmp.fixed.single.$2.code, 'P0301');
    expect(cmp.added.single.$1, '01 · Engine');

    await store.delete(older);
    expect((await store.list('WVWZZZAUZDW123456')).length, 1);
  });

  test('PDF report is generated', () async {
    final current = _record(DateTime.utc(2026, 10, 20), [('P0420', 'Catalyst'), ('P1234', 'Maker specific')]);
    final previous = _record(DateTime.utc(2026, 10, 1), [('P0301', 'Misfire')]);
    final bytes = await buildScanReport(current, previous: previous);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  testWidgets('every scan is saved and compared with the previous one', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final session = DiagSession(
      backupStore: MemoryBackupStore(),
      historyStore: MemoryHistoryStore(),
      demoLatency: Duration.zero,
    );
    await tester.pumpWidget(CarDiagApp(session: session));
    await tester.tap(find.text('Demo car'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();

    Future<void> scan() async {
      await tester.tap(
        find.byTooltip('Scan again').evaluate().isEmpty ? find.text('Scan all modules') : find.byTooltip('Scan again'),
      );
      await tester.pumpAndSettle();
    }

    await scan();
    // Fix the ABS fault (it's only stored, so clearing removes it), then scan again.
    await tester.runAsync(() => UdsClient(session.transport, 0x713, rxId: 0x77D).clearDtcs());
    await scan();

    await tester.tap(find.text('Scan history'));
    await tester.pumpAndSettle();
    expect(find.text('6 faults'), findsOneWidget); // first scan
    expect(find.text('5 faults'), findsOneWidget); // second scan
    expect(find.text('1 gone'), findsOneWidget);

    await tester.tap(find.text('5 faults'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gone · 03 · Brakes (ABS/ESC)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Share PDF report'), 300);
    expect(find.text('Share PDF report'), findsOneWidget);
  });
}
