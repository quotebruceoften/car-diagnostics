/// Diagnostic trouble code encoding/decoding and generic descriptions.
library;

import 'dart:typed_data';

const _systems = 'PCBU';
const _systemNames = {'P': 'Powertrain', 'C': 'Chassis', 'B': 'Body', 'U': 'Network'};

/// Generic (SAE J2012) descriptions for common codes. Brands add their own.
const genericDtcDescriptions = {
  'P0010': 'Camshaft position actuator circuit (bank 1)',
  'P0011': 'Camshaft timing over-advanced (bank 1)',
  'P0016': 'Crankshaft/camshaft position correlation',
  'P0100': 'Mass air flow circuit malfunction',
  'P0101': 'Mass air flow circuit range/performance',
  'P0102': 'Mass air flow circuit low input',
  'P0106': 'MAP/barometric pressure circuit range/performance',
  'P0115': 'Coolant temperature circuit malfunction',
  'P0117': 'Coolant temperature circuit low input',
  'P0118': 'Coolant temperature circuit high input',
  'P0121': 'Throttle position sensor range/performance',
  'P0128': 'Coolant thermostat below regulating temperature',
  'P0130': 'O2 sensor circuit (bank 1 sensor 1)',
  'P0133': 'O2 sensor slow response (bank 1 sensor 1)',
  'P0135': 'O2 sensor heater circuit (bank 1 sensor 1)',
  'P0141': 'O2 sensor heater circuit (bank 1 sensor 2)',
  'P0171': 'System too lean (bank 1)',
  'P0172': 'System too rich (bank 1)',
  'P0174': 'System too lean (bank 2)',
  'P0175': 'System too rich (bank 2)',
  'P0217': 'Engine overtemperature condition',
  'P0234': 'Turbocharger overboost condition',
  'P0299': 'Turbocharger underboost condition',
  'P0300': 'Random/multiple cylinder misfire detected',
  'P0301': 'Cylinder 1 misfire detected',
  'P0302': 'Cylinder 2 misfire detected',
  'P0303': 'Cylinder 3 misfire detected',
  'P0304': 'Cylinder 4 misfire detected',
  'P0305': 'Cylinder 5 misfire detected',
  'P0306': 'Cylinder 6 misfire detected',
  'P0325': 'Knock sensor 1 circuit',
  'P0335': 'Crankshaft position sensor A circuit',
  'P0340': 'Camshaft position sensor circuit',
  'P0401': 'EGR flow insufficient',
  'P0420': 'Catalyst efficiency below threshold (bank 1)',
  'P0430': 'Catalyst efficiency below threshold (bank 2)',
  'P0441': 'EVAP incorrect purge flow',
  'P0442': 'EVAP small leak detected',
  'P0455': 'EVAP large leak detected',
  'P0456': 'EVAP very small leak detected',
  'P0500': 'Vehicle speed sensor',
  'P0505': 'Idle control system',
  'P0562': 'System voltage low',
  'P0563': 'System voltage high',
  'P0700': 'Transmission control system malfunction',
  'P0730': 'Incorrect gear ratio',
  'P0740': 'Torque converter clutch circuit',
  'U0100': 'Lost communication with ECM/PCM',
  'U0101': 'Lost communication with TCM',
  'U0121': 'Lost communication with ABS module',
  'U0140': 'Lost communication with body control module',
  'U0155': 'Lost communication with instrument cluster',
  'C0035': 'Left front wheel speed sensor circuit',
  'C0040': 'Right front wheel speed sensor circuit',
};

const _statusBits = [
  (0x01, 'test failed'),
  (0x02, 'failed this cycle'),
  (0x04, 'pending'),
  (0x08, 'confirmed'),
  (0x10, 'not completed since clear'),
  (0x20, 'failed since clear'),
  (0x40, 'not completed this cycle'),
  (0x80, 'warning lamp'),
];

class Dtc {
  const Dtc(this.code, {this.status, this.failureType});

  final String code;

  /// UDS status byte, when read via UDS.
  final int? status;

  /// UDS failure type byte (third byte of a 3-byte DTC).
  final int? failureType;

  String get display =>
      failureType == null ? code : '$code-${failureType!.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  /// True if the fault is active right now (vs. stored from the past).
  bool get active => status != null && status! & 0x01 != 0;

  List<String> get statusFlags => [
    for (final (bit, name) in _statusBits)
      if (status != null && status! & bit != 0) name,
  ];

  @override
  bool operator ==(Object other) =>
      other is Dtc && other.code == code && other.status == status && other.failureType == failureType;

  @override
  int get hashCode => Object.hash(code, status, failureType);

  @override
  String toString() => display;
}

/// 2-byte SAE J2012 DTC -> "P0301".
String decodeDtc(List<int> b) =>
    '${_systems[b[0] >> 6]}${(b[0] >> 4) & 3}${(b[0] & 0xF).toRadixString(16).toUpperCase()}'
    '${b[1].toRadixString(16).toUpperCase().padLeft(2, '0')}';

/// "P0301" -> 2 bytes.
Uint8List encodeDtc(String code) {
  final c = code.trim().toUpperCase();
  if (c.length != 5 || !_systems.contains(c[0]) || !'0123'.contains(c[1])) {
    throw FormatException('invalid DTC $code');
  }
  final a = (_systems.indexOf(c[0]) << 6) | (int.parse(c[1]) << 4) | int.parse(c[2], radix: 16);
  return Uint8List.fromList([a, int.parse(c.substring(3), radix: 16)]);
}

String describeGenericDtc(String code) {
  final known = genericDtcDescriptions[code];
  if (known != null) return known;
  final system = _systemNames[code.isEmpty ? '' : code[0]] ?? 'Unknown';
  final kind = code.length > 1 && (code[1] == '1' || code[1] == '3') ? 'manufacturer specific' : 'generic';
  return '$system fault ($kind)';
}

/// Parses the body of a mode 03/07/0A reply (after 0x43/0x47/0x4A).
/// On CAN the first byte is the DTC count; 0x0000 pairs are padding.
List<Dtc> parseObdDtcs(List<int> data) {
  if (data.isEmpty) return [];
  final count = data[0];
  final out = <Dtc>[];
  for (var i = 1; i + 1 < data.length && out.length < count; i += 2) {
    if (data[i] == 0 && data[i + 1] == 0) continue;
    out.add(Dtc(decodeDtc([data[i], data[i + 1]])));
  }
  return out;
}
