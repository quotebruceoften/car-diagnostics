/// Readiness monitors (mode 01, PID 01): which emissions self-tests have run
/// since the fault codes were last cleared. Inspections check these.
library;

class Monitor {
  const Monitor(this.name, {required this.complete, this.continuous = false});
  final String name;
  final bool complete;

  /// Misfire, fuel system and components run all the time while driving.
  final bool continuous;
}

enum ReadinessVerdict { ready, almostReady, notReady }

class Readiness {
  const Readiness({required this.milOn, required this.dtcCount, required this.diesel, required this.monitors});

  final bool milOn;
  final int dtcCount;
  final bool diesel;

  /// Only the monitors this car supports.
  final List<Monitor> monitors;

  List<Monitor> get incomplete => monitors.where((m) => !m.complete).toList();

  /// Many inspection schemes accept one incomplete monitor (rules vary by
  /// country and model year), never a lit check engine light.
  ReadinessVerdict get verdict {
    if (milOn) return ReadinessVerdict.notReady;
    final n = incomplete.length;
    if (n == 0) return ReadinessVerdict.ready;
    return n == 1 ? ReadinessVerdict.almostReady : ReadinessVerdict.notReady;
  }
}

const _sparkMonitors = [
  'Catalytic converter',
  'Heated catalyst',
  'Fuel vapour (EVAP) system',
  'Secondary air system',
  'A/C refrigerant',
  'Oxygen sensors',
  'Oxygen sensor heaters',
  'EGR / variable valve timing',
];

const _dieselMonitors = [
  'NMHC catalyst',
  'NOx / SCR aftertreatment',
  null,
  'Boost pressure system',
  null,
  'Exhaust gas sensors',
  'Particulate filter',
  'EGR / variable valve timing',
];

/// Decodes the four data bytes (A-D) of a mode 01 PID 01 reply.
///
/// Byte B: bits 0-2 say whether misfire, fuel system and component monitors
/// exist, bits 4-6 are set while they are *not* complete; bit 3 marks a
/// diesel. Bytes C and D do the same for the engine-type specific monitors.
Readiness decodeReadiness(List<int> d) {
  if (d.length < 4) throw ArgumentError('readiness needs 4 bytes');
  final a = d[0], b = d[1], c = d[2], incomplete = d[3];
  final diesel = b & 0x08 != 0;
  final monitors = <Monitor>[
    for (final (bit, name) in [(0, 'Misfire'), (1, 'Fuel system'), (2, 'Components')])
      if (b & (1 << bit) != 0) Monitor(name, complete: b & (1 << (bit + 4)) == 0, continuous: true),
  ];
  final names = diesel ? _dieselMonitors : _sparkMonitors;
  for (var bit = 0; bit < 8; bit++) {
    final name = names[bit];
    if (name != null && c & (1 << bit) != 0) {
      monitors.add(Monitor(name, complete: incomplete & (1 << bit) == 0));
    }
  }
  return Readiness(milOn: a & 0x80 != 0, dtcCount: a & 0x7F, diesel: diesel, monitors: monitors);
}
