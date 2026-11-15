import 'dart:typed_data';

import 'package:cardiag_mobile/core/coding/coder.dart';
import 'package:cardiag_mobile/core/error_log.dart';
import 'package:cardiag_mobile/core/history.dart';
import 'package:cardiag_mobile/core/service_log.dart';
import 'package:cardiag_mobile/core/support_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the error log keeps recent messages once each', () {
    final log = ErrorLog.instance..clear();
    final t = DateTime(2026, 11, 15, 12);
    log.record('Could not connect to IOS-Vlink', at: t);
    log.record('Could not connect to IOS-Vlink', at: t.add(const Duration(seconds: 30))); // redrawn panel
    log.record('Module rejected the request', at: t.add(const Duration(minutes: 1)));
    log.record('Could not connect to IOS-Vlink', at: t.add(const Duration(minutes: 10))); // happened again
    expect(
      [for (final (_, m) in log.entries) m],
      ['Could not connect to IOS-Vlink', 'Module rejected the request', 'Could not connect to IOS-Vlink'],
    );
    for (var i = 0; i < 60; i++) {
      log.record('error $i', at: t.add(Duration(hours: 1, minutes: i * 3)));
    }
    expect(log.entries, hasLength(40));
    expect(log.entries.last.$2, 'error 59');
    log.clear();
  });

  test('the developer report has every section', () {
    final text = buildSupportReport(
      appVersion: '0.3.0 (build 31)',
      now: DateTime(2026, 11, 15, 12, 30),
      car: 'Volkswagen Golf 7 · 2013',
      vin: 'WVWZZZAUZDW000001',
      adapter: 'ELM327 v2.3 via IOS-Vlink',
      connected: true,
      latestScan: ScanRecord(
        timestamp: DateTime(2026, 11, 15, 12),
        vin: 'WVWZZZAUZDW000001',
        carName: 'Golf',
        modules: const [
          ModuleRecord(
            address: '09',
            name: 'Central electrics',
            faults: [FaultRecord(code: 'B1263', display: 'B1263-01', description: 'Fuel tank flap', number: 197644)],
          ),
        ],
      ),
      explorerResults: {'17': 'F187  35 47    "5G0920861B"'},
      codingBackups: [
        CodingBackup(
          moduleName: 'Instrument cluster',
          txId: 0x714,
          did: 0x0600,
          data: Uint8List.fromList([0x27, 0xA4]),
          timestamp: DateTime(2026, 11, 15, 11),
          partNumber: '5G0920861B',
        ),
      ],
      serviceLog: ServiceLog(mileage: 144873)
        ..upsert(ServiceEntry(id: '1', type: ServiceType.oil, date: DateTime(2026, 3, 3), km: 134489)),
      counters: 'odometer 144873 km',
      errors: [(DateTime(2026, 11, 15, 12, 10), 'Module rejected the request: request out of range')],
      settings: {'temp': 'celsius'},
    );
    expect(text, contains('App: 0.3.0 (build 31)'));
    expect(text, contains('Adapter: ELM327 v2.3 via IOS-Vlink'));
    expect(text, contains('From the car: odometer 144873 km'));
    expect(text, contains('2026-11-15 12:10  Module rejected the request: request out of range'));
    expect(text, contains('B1263-01  Fuel tank flap'));
    expect(text, contains('Instrument cluster 5G0920861B  27A4'));
    expect(text, contains('2026-03-03  Oil and filter change at 134489 km'));
    expect(text, contains('==== Module explorer: 17 ===='));
    expect(text, contains('"temp": "celsius"'));
  });
}
