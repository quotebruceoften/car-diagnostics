import 'package:cardiag_mobile/core/transport/elm327.dart';
import 'package:cardiag_mobile/core/transport/transport.dart';
import 'package:cardiag_mobile/sim/elm_emulator.dart';
import 'package:cardiag_mobile/sim/vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

typedef TransportFactory = Future<Transport> Function(Vehicle vehicle);

/// Every client test runs directly against the simulator and through the
/// emulated ELM327, which exercises the real adapter driver.
final transportFactories = <String, TransportFactory>{
  'simulator': (v) async => SimulatorTransport(v),
  'elm327': (v) async {
    final t = Elm327Transport(Elm327Emulator(v));
    await t.initialize();
    return t;
  },
};

void forEachTransport(void Function(String name, Future<(Transport, Vehicle)> Function() setup) body) {
  for (final e in transportFactories.entries) {
    group(e.key, () {
      body(e.key, () async {
        final v = Vehicle.demoGolf();
        return (await e.value(v), v);
      });
    });
  }
}
