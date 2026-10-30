import 'dart:convert';

import 'package:cardiag_mobile/core/history.dart';
import 'package:cardiag_mobile/core/vcds_import.dart';
import 'package:cardiag_mobile/ui/screens/history_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shortened VCDS auto-scan log in VCDS's own layout (made-up VIN).
const _log = '''
Thursday,29,October,2026,17:06:16:00009
VCDS -- Windows Based VAG/VAS Emulator Running on Windows 11 x64
VCDS Version: 23.11.0.0
www.Ross-Tech.com


VIN: WVWZZZAUZDW000001   License Plate: 
Mileage: 144472km-89770mi   Repair Order: 

--------------------------------------------------------------------------------

Chassis Type: AU-VW37 (5Q0)
Scan: 01 03 09 17 52

01-Engine -- Status: OK 0000
 
-------------------------------------------------------------------------------
Address 01: Engine (J623-CPTA)       Labels:. 04E-907-309-V1.clb
   Part No SW: 04E 906 016 CH    HW: 04E 907 309 G
   Component: 1,4l R4 TSI   H02 5759  
   Coding: 01250012236405082000

2 Faults Found:
17158 - Databus 
          U1123 00 [00100000] - Received Error Message
          Intermittent - Not Confirmed - Tested Since Memory Clear

4511 - Camshaft Position Sensor B Bank 1 (G300) 
          P0366 00 [01100000] - Implausible Signal
          Intermittent - Not Confirmed - Tested Since Memory Clear

Readiness: 0000 0000

-------------------------------------------------------------------------------
Address 03: ABS Brakes (J104)       Labels: 5Q0-907-379-IPB-V1.clb
   Part No SW: 5Q0 907 379 AD    HW: 5Q0 907 379 E

1 Fault Found:
0297 - ROD - Unknown Error Code 
          - 00 [00001000]
          Intermittent - Confirmed - Tested Since Memory Clear
             Freeze Frame:
                    Fault Priority: 2
                    Mileage: 137324 km

-------------------------------------------------------------------------------
Address 09: Cent. Elect. (J519)       Labels:| 5Q0-937-08X-HV1.clb
   Part No SW: 5Q0 937 085 M    HW: 5Q0 937 085 M

   Wiper motor control module: 
   Subsystem 1 - Part No SW: 5G2 955 119 A    HW: 5G2 955 119 A  Labels: 5QX-955-119-V1.CLB

1 Fault Found:
197644 - Control Circuit for Fuel Tank Flap 
          B1263 01 [00001001] - Electrical Failure
          Confirmed - Tested Since Memory Clear
             Freeze Frame:
                    Outside temperature: 32.5 °C

-------------------------------------------------------------------------------
Address 17: Instruments (J285)       Labels:| 5G0-920-XXX-17.clb-SRI3
   Part No SW: 5G0 920 861 B    HW: 5G0 920 861 B

No fault code found.

End-------------------------(Elapsed Time: 04:20)--------------------------
''';

ScanRecord _scan(DateTime t, Map<String, List<String>> faults) => ScanRecord(
  timestamp: t,
  vin: 'V',
  carName: 'Golf',
  modules: [
    for (final e in faults.entries)
      ModuleRecord(
        address: e.key,
        name: 'M${e.key}',
        faults: [for (final c in e.value) FaultRecord(code: c, display: c, description: c)],
      ),
  ],
);

void main() {
  group('VCDS import', () {
    test('reads the header, modules and faults', () {
      final log = parseVcdsLog(_log, carName: (vin) => 'Golf ($vin)');
      final r = log.record;
      expect(r.vin, 'WVWZZZAUZDW000001');
      expect(r.timestamp, DateTime(2026, 10, 29, 17, 6, 16));
      expect(r.source, 'VCDS');
      expect(r.carName, 'Golf (WVWZZZAUZDW000001)');
      expect(log.mileageKm, 144472);
      expect([for (final m in r.modules) m.address], ['01', '03', '09', '17']);
      expect(r.faultCount, 4);

      final engine = r.modules[0];
      expect(engine.name, 'Engine');
      expect(engine.partNumber, '04E 906 016 CH');
      expect(engine.faults[1].code, 'P0366');
      expect(engine.faults[1].display, 'P0366-00');
      expect(engine.faults[1].description, 'Camshaft Position Sensor B Bank 1 (G300): Implausible Signal');
      expect(engine.faults[1].active, isFalse);

      // A fault without a code keeps VCDS's number.
      expect(r.modules[1].faults.single.code, '0297');
      expect(r.modules[1].faults.single.description, 'ROD - Unknown Error Code');
      // Subsystem part numbers don't replace the module's own.
      expect(r.modules[2].partNumber, '5Q0 937 085 M');
      expect(r.modules[2].faults.single.active, isTrue);
      expect(r.modules[3].faults, isEmpty);
      expect(r.modules[3].faultsReadable, isTrue);
    });

    test('decodes Windows-1252 files and rejects other files', () {
      expect(decodeVcdsBytes(latin1.encode('32.5 °C')), '32.5 °C');
      expect(decodeVcdsBytes(utf8.encode('32.5 °C')), '32.5 °C');
      expect(() => parseVcdsLog('hello', carName: (_) => ''), throwsFormatException);
      expect(() => parseVcdsLog('VCDS\nnothing here', carName: (_) => ''), throwsFormatException);
    });

    test('module names follow the app and the record round-trips', () {
      final r = withBrandModuleNames(parseVcdsLog(_log, carName: (_) => 'Golf').record);
      expect(
        [for (final m in r.modules) m.name],
        ['Engine', 'Brakes (ABS/ESC)', 'Central electrics', 'Instrument cluster'],
      );
      final back = ScanRecord.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.source, 'VCDS');
      expect(back.faultCount, 4);
    });
  });

  group('fault trends', () {
    test('count recurring, new and gone faults', () {
      final trends = FaultTrends([
        _scan(DateTime(2026, 3, 3), {
          '01': ['P0366'],
          '09': ['B1263'],
        }),
        _scan(DateTime(2026, 7, 6), {
          '01': ['P0366', 'U0428'],
          '09': ['B1263'],
        }),
        _scan(DateTime(2026, 10, 29), {
          '01': ['P0366', 'U1123'],
        }),
      ]);
      expect(trends.scans, 3);
      final all = trends.all;
      expect(all.first.fault.code, 'P0366');
      expect(describeTrend(all.first), 'In 3 of 3 scans since 2026-03-03');
      final u1123 = all.firstWhere((t) => t.fault.code == 'U1123');
      expect(describeTrend(u1123), 'New in the latest scan');
      final flap = all.firstWhere((t) => t.fault.code == 'B1263');
      expect(flap.current, isFalse);
      expect(describeTrend(flap), 'Gone since 2026-10-29 · seen 2×');
      final steering = all.firstWhere((t) => t.fault.code == 'U0428');
      expect(describeTrend(steering), 'Gone since 2026-10-29 · seen 1×');
      expect(all.last.current, isFalse);
    });

    test('scans from different tools line up by module address and code', () {
      final app = _scan(DateTime(2026, 11, 1), {
        '01': ['P0366'],
      });
      final vcds = ScanRecord(
        timestamp: DateTime(2026, 10, 29),
        vin: 'V',
        carName: 'Golf',
        source: 'VCDS',
        modules: const [
          ModuleRecord(
            address: '01',
            name: 'Engine (VCDS name)',
            faults: [FaultRecord(code: 'P0366', display: 'P0366-00', description: 'x')],
          ),
        ],
      );
      expect(ScanComparison(app, vcds).added, isEmpty);
      final t = FaultTrends([app, vcds]).find('01', 'Engine', 'p0366')!;
      expect(t.seen, 2);
      expect(t.current, isTrue);
    });

    test('a fault that went away and came back is current again', () {
      final trends = FaultTrends([
        _scan(DateTime(2026, 1, 1), {
          '01': ['P0366'],
        }),
        _scan(DateTime(2026, 2, 1), {}),
        _scan(DateTime(2026, 3, 1), {
          '01': ['P0366'],
        }),
      ]);
      final t = trends.all.single;
      expect(t.current, isTrue);
      expect(t.goneSince, isNull);
      expect(describeTrend(t), 'In 2 of 3 scans since 2026-01-01');
    });
  });
}
