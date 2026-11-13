import 'dart:async';

import 'package:cardiag_mobile/core/coding/security.dart';
import 'package:cardiag_mobile/core/transport/byte_channel.dart';
import 'package:cardiag_mobile/core/transport/elm327.dart';
import 'package:cardiag_mobile/core/errors.dart';
import 'package:cardiag_mobile/core/obd/obd_client.dart';
import 'package:cardiag_mobile/core/uds/uds_client.dart';
import 'package:cardiag_mobile/sim/elm_emulator.dart';
import 'package:cardiag_mobile/sim/vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  adapterTests();
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

/// An adapter that accepts the connection but never speaks ELM327.
class _SilentChannel implements ByteChannel {
  final _incoming = StreamController<List<int>>();

  @override
  String get name => 'silent';

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> write(List<int> data) async => _incoming.close();

  @override
  Future<void> close() async {}
}

void adapterTests() {
  test('explains when an adapter is not an ELM327', () async {
    await expectLater(
      Elm327Transport(_SilentChannel()).initialize(),
      throwsA(
        isA<TransportException>().having((e) => e.message, 'message', contains('does not respond like an ELM327')),
      ),
    );
  });

  group('connecting through the adapter', () {
    test('falls back to explicit CAN protocols when automatic search fails', () async {
      final elm = Elm327Emulator()..autoSearchWorks = false;
      final t = Elm327Transport(elm);
      await t.initialize();
      expect(t.protocolNumber, 6);
      expect(elm.log, containsAllInOrder(['ATSP0', '0100', 'ATSP6', '0100']));
      expect(await ObdClient(t).vin(), 'WVWZZZAUZHW123456');
    });

    test('explains that the ignition is off, with the adapter details', () async {
      final t = Elm327Transport(Elm327Emulator()..ignitionOn = false);
      await expectLater(
        t.initialize(),
        throwsA(
          isA<NoResponseException>().having(
            (e) => e.message,
            'message',
            allOf(contains('ELM327 v1.5'), contains(' V)'), contains('ignition')),
          ),
        ),
      );
    });
  });

  group('real-car behaviour', () {
    test('modules outside the OBD range answer with long replies through the adapter', () async {
      final elm = Elm327Emulator();
      final t = Elm327Transport(elm);
      await t.initialize();
      // The part number is longer than one CAN frame, so it needs flow control.
      final part = await UdsClient(t, 0x713, rxId: 0x77D).readDataByIdentifier(0xF187);
      expect(String.fromCharCodes(part), '5Q0907379Q');
      expect(elm.log, containsAllInOrder(['ATSH713', 'ATFCSH713', 'ATFCSD300000', 'ATFCSM1']));
      // Back to the engine: the adapter's standard flow control again.
      expect(await ObdClient(t).vin(), 'WVWZZZAUZHW123456');
      expect(elm.log.last == 'ATFCSM0' || elm.log.contains('ATFCSM0'), isTrue);
    });

    test('self-tests that have not run are not reported as faults', () async {
      final uds = UdsClient(SimulatorTransport(Vehicle.demoGolf()), 0x7E0, rxId: 0x7E8);
      expect([for (final d in await uds.readDtcs()) d.code], ['P0301', 'P0420', 'P0171']);
      expect(await uds.readDtcs(0xFF), hasLength(5)); // what the module lists in total
    });
  });
}
