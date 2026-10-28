import 'package:cardiag_mobile/core/coding/security.dart';
import 'package:cardiag_mobile/core/errors.dart';
import 'package:cardiag_mobile/core/obd/obd_client.dart';
import 'package:cardiag_mobile/core/uds/uds_client.dart';
import 'package:cardiag_mobile/sim/vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  forEachTransport((name, setup) {
    test('VIN and supported PIDs across ECUs', () async {
      final (t, _) = await setup();
      final obd = ObdClient(t);
      expect(await obd.vin(), 'WVWZZZAUZHW123456');
      final supported = await obd.supportedPids();
      expect(supported.keys.toSet(), {0x7E8, 0x7E9});
      expect(supported[0x7E8], containsAll([0x0C, 0x0D, 0x42, 0x5C]));
      expect(supported[0x7E8], isNot(contains(0x20)));
    });

    test('live values', () async {
      final (t, _) = await setup();
      final obd = ObdClient(t);
      final rpm = await obd.read('rpm');
      expect(rpm.numeric, inInclusiveRange(800, 2600));
      expect('${await obd.read('baro_pressure')}', '101 kPa');
      final status = await obd.monitorStatus();
      expect(status.milOn, isTrue);
      expect(status.dtcCount, 2);
    });

    test('OBD fault codes, freeze frame and clearing', () async {
      final (t, _) = await setup();
      final obd = ObdClient(t);
      expect((await obd.readDtcs())[0x7E8]!.map((d) => d.code), ['P0301', 'P0420']);
      expect((await obd.readDtcs(DtcKind.pending))[0x7E9]!.map((d) => d.code), ['P0730']);
      final ff = await obd.freezeFrame();
      expect(ff!.$1, 'P0301');
      expect(ff.$2.map((r) => r.pid.name), contains('rpm'));
      expect(await obd.clearDtcs(), [0x7E8, 0x7E9]);
      expect((await obd.readDtcs())[0x7E8], isEmpty);
      expect((await obd.readDtcs(DtcKind.permanent))[0x7E8]!.map((d) => d.code), ['P0420']);
      expect(await obd.freezeFrame(), isNull);
    });

    test('UDS identification and negative responses', () async {
      final (t, _) = await setup();
      final uds = UdsClient(t, 0x70E, rxId: 0x778);
      expect(String.fromCharCodes(await uds.readDataByIdentifier(0xF187)), '5Q0937DEMO');
      await expectLater(
        uds.readDataByIdentifier(0x1234),
        throwsA(isA<NegativeResponseException>().having((e) => e.nrc, 'nrc', 0x31)),
      );
      await expectLater(UdsClient(t, 0x773, rxId: 0x7DD).testerPresent(), throwsA(isA<NoResponseException>()));
    });

    test('UDS fault codes; active faults survive clearing', () async {
      final (t, _) = await setup();
      final abs = UdsClient(t, 0x713, rxId: 0x77D);
      final [dtc] = await abs.readDtcs();
      expect(dtc.display, 'C0035-1F');
      await abs.clearDtcs();
      expect(await abs.readDtcs(), isEmpty);
      final engine = UdsClient(t, 0x7E0);
      expect((await engine.readDtcs(0x04)).map((d) => d.code), ['P0171']);
      await engine.clearDtcs();
      expect((await engine.readDtcs()).map((d) => d.code), ['P0301']); // still misfiring
    });

    test('long (multi-frame) UDS reads', () async {
      final (t, _) = await setup();
      final coding = await UdsClient(t, 0x70E, rxId: 0x778).readDataByIdentifier(0x0600);
      expect(coding.length, 30);
    });
  });

  test('security access with the demo algorithm', () async {
    final v = Vehicle.demoGolf();
    v.ecu(0x70E)!
      ..writableDids.remove(0x0600)
      ..securedDids.add(0x0600);
    final uds = UdsClient(SimulatorTransport(v), 0x70E, rxId: 0x778);
    await expectLater(
      uds.securityAccess(3, demoXor),
      throwsA(isA<NegativeResponseException>().having((e) => e.nrc, 'nrc', 0x7F)),
    );
    await uds.diagnosticSessionControl(extendedSession);
    await expectLater(
      uds.writeDataByIdentifier(0x0600, List.filled(30, 0)),
      throwsA(isA<NegativeResponseException>().having((e) => e.nrc, 'nrc', 0x33)),
    );
    await expectLater(
      uds.securityAccess(3, (seed, level) => seed),
      throwsA(isA<NegativeResponseException>().having((e) => e.nrc, 'nrc', 0x35)),
    );
    await uds.securityAccess(3, demoXor);
    await uds.securityAccess(3, demoXor); // zero seed: already unlocked
    await uds.writeDataByIdentifier(0x0600, List.filled(30, 0));
    expect(await uds.readDataByIdentifier(0x0600), List.filled(30, 0));
  });
}
