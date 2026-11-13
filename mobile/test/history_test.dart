import 'dart:io';

import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/history.dart';
import 'package:cardiag_mobile/core/scan_export.dart';
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

  test('details file lists modules, raw fault numbers and status', () {
    final text = scanDetailsText(
      ScanRecord(
        timestamp: DateTime(2026, 11, 13, 12, 21),
        vin: 'WVWZZZAUZDW000001',
        carName: 'Volkswagen Golf 7 · 2013',
        modules: const [
          ModuleRecord(
            address: '09',
            name: 'Central electrics',
            partNumber: '5Q0937085M',
            faults: [
              FaultRecord(
                code: 'B1263',
                display: 'B1263-01',
                description: 'Fuel tank flap control circuit fault',
                active: true,
                number: 197644,
                status: 0x09,
              ),
            ],
          ),
          ModuleRecord(address: '15', name: 'Airbags', faults: []),
        ],
      ),
      notFound: ['55 Headlight range'],
      adapter: 'ELM327 v2.3 via IOS-Vlink',
      appVersion: '0.3.0 (build 20)',
    );
    expect(text, contains('VIN: WVWZZZAUZDW000001'));
    expect(text, contains('Scanned: 2026-11-13 12:21'));
    expect(text, contains('--- 09 · Central electrics   part 5Q0937085M'));
    expect(text, contains('B1263-01  Fuel tank flap control circuit fault'));
    expect(text, contains('number 197644 (0x03040C)   status 0x09: test failed, confirmed'));
    expect(text, contains('--- 15 · Airbags'));
    expect(text, contains('no faults'));
    expect(text, contains('55 Headlight range'));
    expect(text, contains('Adapter: ELM327 v2.3 via IOS-Vlink'));
  });
}
