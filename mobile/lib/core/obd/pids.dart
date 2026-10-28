/// SAE J1979 mode 01 / 02 parameter IDs and their decoders.
library;

import '../errors.dart';

class Pid {
  const Pid(this.pid, this.name, this.description, this.unit, this.length, this.decode, {this.min = 0, this.max = 100});

  final int pid;
  final String name;
  final String description;
  final String unit;
  final int length;
  final Object Function(List<int> d) decode;

  /// Typical display range, used for gauges.
  final double min;
  final double max;
}

int _u16(List<int> d) => (d[0] << 8) | d[1];
double _round(double v, [int places = 1]) => double.parse(v.toStringAsFixed(places));
double _pct(List<int> d) => _round(d[0] * 100 / 255);
double _trim(List<int> d) => _round((d[0] - 128) * 100 / 128);
int _temp(List<int> d) => d[0] - 40;

class MonitorStatus {
  const MonitorStatus({required this.milOn, required this.dtcCount});
  final bool milOn;
  final int dtcCount;

  @override
  String toString() => 'MIL ${milOn ? 'on' : 'off'}, $dtcCount DTCs';
}

const _fuelSystem = {
  0: 'off',
  1: 'open loop (cold)',
  2: 'closed loop',
  4: 'open loop (load/decel)',
  8: 'open loop (fault)',
  16: 'closed loop (fault)',
};

final List<Pid> allPids = [
  Pid(
    0x01,
    'monitor_status',
    'Monitor status',
    '',
    4,
    (d) => MonitorStatus(milOn: d[0] & 0x80 != 0, dtcCount: d[0] & 0x7F),
  ),
  Pid(0x03, 'fuel_system', 'Fuel system status', '', 2, (d) => _fuelSystem[d[0]] ?? '0x${d[0].toRadixString(16)}'),
  Pid(0x04, 'engine_load', 'Engine load', '%', 1, _pct),
  Pid(0x05, 'coolant_temp', 'Coolant temperature', '°C', 1, _temp, min: -40, max: 130),
  Pid(0x06, 'stft_b1', 'Short term fuel trim B1', '%', 1, _trim, min: -25, max: 25),
  Pid(0x07, 'ltft_b1', 'Long term fuel trim B1', '%', 1, _trim, min: -25, max: 25),
  Pid(0x08, 'stft_b2', 'Short term fuel trim B2', '%', 1, _trim, min: -25, max: 25),
  Pid(0x09, 'ltft_b2', 'Long term fuel trim B2', '%', 1, _trim, min: -25, max: 25),
  Pid(0x0A, 'fuel_pressure', 'Fuel pressure', 'kPa', 1, (d) => d[0] * 3, max: 765),
  Pid(0x0B, 'intake_map', 'Intake manifold pressure', 'kPa', 1, (d) => d[0], max: 255),
  Pid(0x0C, 'rpm', 'Engine speed', 'rpm', 2, (d) => _u16(d) / 4, max: 7000),
  Pid(0x0D, 'speed', 'Vehicle speed', 'km/h', 1, (d) => d[0], max: 250),
  Pid(0x0E, 'timing_advance', 'Timing advance', '°', 1, (d) => d[0] / 2 - 64, min: -20, max: 60),
  Pid(0x0F, 'intake_temp', 'Intake air temperature', '°C', 1, _temp, min: -40, max: 80),
  Pid(0x10, 'maf', 'Mass air flow', 'g/s', 2, (d) => _u16(d) / 100, max: 250),
  Pid(0x11, 'throttle', 'Throttle position', '%', 1, _pct),
  Pid(0x1F, 'run_time', 'Run time since start', 's', 2, _u16, max: 3600),
  Pid(0x21, 'distance_mil', 'Distance with MIL on', 'km', 2, _u16, max: 10000),
  Pid(0x2F, 'fuel_level', 'Fuel level', '%', 1, _pct),
  Pid(0x31, 'distance_since_clear', 'Distance since codes cleared', 'km', 2, _u16, max: 10000),
  Pid(0x33, 'baro_pressure', 'Barometric pressure', 'kPa', 1, (d) => d[0], min: 70, max: 110),
  Pid(0x42, 'module_voltage', 'Control module voltage', 'V', 2, (d) => _u16(d) / 1000, min: 10, max: 16),
  Pid(0x46, 'ambient_temp', 'Ambient temperature', '°C', 1, _temp, min: -40, max: 60),
  Pid(0x49, 'accel_pedal_d', 'Accelerator pedal', '%', 1, _pct),
  Pid(0x5C, 'oil_temp', 'Oil temperature', '°C', 1, _temp, min: -40, max: 150),
  Pid(0x5E, 'fuel_rate', 'Fuel rate', 'L/h', 2, (d) => _u16(d) / 20, max: 30),
];

final Map<int, Pid> pidsByNumber = {for (final p in allPids) p.pid: p};
final Map<String, Pid> pidsByName = {for (final p in allPids) p.name: p};

Pid lookupPid(Object key) {
  final pid = key is int ? pidsByNumber[key] : pidsByName['$key'.toLowerCase()];
  if (pid == null) throw CarDiagException('Unknown PID $key');
  return pid;
}

/// Decodes a "PIDs supported [base+1 .. base+0x20]" bitmap.
Set<int> decodeSupported(int base, List<int> data) {
  final bits = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
  return {
    for (var i = 0; i < 32; i++)
      if (bits & (1 << (31 - i)) != 0) base + i + 1,
  };
}
