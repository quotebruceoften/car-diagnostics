/// Plain-language explanations of fault codes.
///
/// Entries cover common generic (SAE J2012) codes with general, widely
/// documented causes. They are guidance, not a diagnosis: the same code can
/// have different causes on different engines.
library;

enum Severity {
  low('Minor', 'Fix when convenient'),
  medium('Moderate', 'Get it checked soon'),
  high('Serious', 'Get it checked as soon as possible'),
  critical('Stop driving', 'Stop safely and get help');

  const Severity(this.label, this.advice);
  final String label;
  final String advice;
}

class DtcInfo {
  const DtcInfo({
    required this.title,
    required this.meaning,
    required this.severity,
    this.causes = const [],
    required this.driving,
    this.isGeneric = false,
  });

  final String title;
  final String meaning;
  final Severity severity;
  final List<String> causes;

  /// Can the car still be driven, and how.
  final String driving;

  /// True when the explanation comes from the code's category, not a specific entry.
  final bool isGeneric;
}

const _misfireCauses = [
  'Worn spark plugs',
  'Faulty ignition coil',
  'Clogged or leaking fuel injector',
  'Vacuum (air) leak',
  'Low compression (mechanical engine problem)',
];
const _misfireDriving =
    'Drive gently and have it checked soon. If the check engine light is flashing, stop driving: '
    'unburnt fuel can overheat and destroy the catalytic converter.';

DtcInfo _misfire(int? cylinder) => DtcInfo(
  title: cylinder == null ? 'Engine misfires on several cylinders' : 'Cylinder $cylinder misfires',
  meaning: cylinder == null
      ? 'The engine computer detected misfires on more than one cylinder or on varying cylinders. The engine may '
            'run rough, shake at idle or lack power.'
      : 'Cylinder $cylinder is not burning its fuel properly. The engine may run rough, shake at idle or lack '
            'power. Swapping that cylinder\'s coil with a neighbour and seeing if the misfire moves is a common test.',
  severity: Severity.high,
  causes: _misfireCauses,
  driving: _misfireDriving,
);

const _o2Causes = ['Faulty oxygen (lambda) sensor', 'Damaged wiring or connector', 'Exhaust leak near the sensor'];
const _commCauses = [
  'Weak or recently disconnected battery (very common)',
  'Loose connector or damaged wiring',
  'Faulty module',
];
const _commDriving =
    'Depends on which module is unreachable. Check the battery first; if warning lights stay on, have it '
    'checked soon.';

final Map<String, DtcInfo> _known = {
  for (var c = 1; c <= 8; c++) 'P030$c': _misfire(c),
  'P0300': _misfire(null),
  'P0171': const DtcInfo(
    title: 'Engine running lean (bank 1)',
    meaning:
        'The engine is getting too much air or too little fuel, and the computer has reached the limit of what '
        'it can correct.',
    severity: Severity.medium,
    causes: [
      'Vacuum (air) leak, e.g. a cracked hose or intake gasket',
      'Dirty or faulty mass air flow sensor',
      'Weak fuel pump or clogged fuel filter',
      'Faulty crankcase ventilation (PCV) valve',
    ],
    driving: 'Usually fine to drive short term, but get it fixed: running lean can cause misfires and engine wear.',
  ),
  'P0174': const DtcInfo(
    title: 'Engine running lean (bank 2)',
    meaning: 'Same as P0171 for the second bank of a V engine: too much air or too little fuel.',
    severity: Severity.medium,
    causes: ['Vacuum (air) leak', 'Dirty or faulty mass air flow sensor', 'Low fuel pressure'],
    driving: 'Usually fine to drive short term, but get it fixed.',
  ),
  'P0172': const DtcInfo(
    title: 'Engine running rich (bank 1)',
    meaning: 'The engine is getting too much fuel or too little air.',
    severity: Severity.medium,
    causes: ['Leaking fuel injector', 'Faulty mass air flow sensor', 'Fuel pressure too high', 'Faulty oxygen sensor'],
    driving: 'Usually drivable, but fuel consumption rises and the catalytic converter can be damaged over time.',
  ),
  'P0175': const DtcInfo(
    title: 'Engine running rich (bank 2)',
    meaning: 'Same as P0172 for the second bank of a V engine.',
    severity: Severity.medium,
    causes: ['Leaking fuel injector', 'Faulty mass air flow sensor', 'Fuel pressure too high'],
    driving: 'Usually drivable short term.',
  ),
  'P0420': const DtcInfo(
    title: 'Catalytic converter not working well enough (bank 1)',
    meaning:
        'The oxygen sensor after the catalytic converter shows that the converter is no longer cleaning the '
        'exhaust as well as it should.',
    severity: Severity.medium,
    causes: [
      'Worn-out catalytic converter',
      'Faulty rear oxygen sensor',
      'Exhaust leak',
      'Earlier misfires that damaged the converter',
    ],
    driving: 'Safe to drive, but the car will likely fail an emissions inspection until it is fixed.',
  ),
  'P0430': const DtcInfo(
    title: 'Catalytic converter not working well enough (bank 2)',
    meaning: 'Same as P0420 for the second bank of a V engine.',
    severity: Severity.medium,
    causes: ['Worn-out catalytic converter', 'Faulty rear oxygen sensor', 'Exhaust leak'],
    driving: 'Safe to drive, but the car will likely fail an emissions inspection.',
  ),
  'P0128': const DtcInfo(
    title: 'Engine takes too long to warm up',
    meaning: 'The coolant did not reach normal operating temperature in the expected time.',
    severity: Severity.low,
    causes: ['Thermostat stuck open', 'Faulty coolant temperature sensor', 'Low coolant level'],
    driving: 'Safe to drive. Expect higher fuel consumption and a weaker heater until fixed.',
  ),
  'P0100': const DtcInfo(
    title: 'Mass air flow sensor circuit fault',
    meaning: 'The sensor that measures air entering the engine is giving an invalid signal.',
    severity: Severity.medium,
    causes: ['Faulty mass air flow sensor', 'Damaged wiring or connector'],
    driving: 'Usually drivable but the engine may run poorly or with reduced power.',
  ),
  'P0101': const DtcInfo(
    title: 'Mass air flow sensor reading implausible',
    meaning: 'The measured air flow does not match what the engine computer expects.',
    severity: Severity.medium,
    causes: ['Dirty mass air flow sensor', 'Air leak after the sensor', 'Clogged air filter', 'Faulty sensor'],
    driving: 'Usually drivable; may cause poor running or higher fuel use.',
  ),
  'P0102': const DtcInfo(
    title: 'Mass air flow sensor signal too low',
    meaning: 'The air flow sensor reports less air than is plausible.',
    severity: Severity.medium,
    causes: ['Faulty sensor', 'Damaged wiring or connector', 'Dirty sensor'],
    driving: 'Usually drivable; may cause poor running.',
  ),
  'P0115': const DtcInfo(
    title: 'Coolant temperature sensor circuit fault',
    meaning: 'The engine computer cannot read the coolant temperature correctly.',
    severity: Severity.medium,
    causes: ['Faulty coolant temperature sensor', 'Damaged wiring or connector'],
    driving:
        'Drive carefully and keep an eye on the temperature gauge; the cooling fan may run constantly and '
        'starting can be harder.',
  ),
  'P0117': const DtcInfo(
    title: 'Coolant temperature sensor signal too low',
    meaning: 'The coolant temperature sensor reports an implausibly low value (often a short circuit).',
    severity: Severity.medium,
    causes: ['Faulty sensor', 'Wiring shorted to ground'],
    driving: 'Drive carefully and watch the temperature gauge.',
  ),
  'P0118': const DtcInfo(
    title: 'Coolant temperature sensor signal too high',
    meaning: 'The coolant temperature sensor reports an implausibly high value (often an open circuit).',
    severity: Severity.medium,
    causes: ['Faulty sensor', 'Broken wire or loose connector'],
    driving: 'Drive carefully and watch the temperature gauge.',
  ),
  'P0121': const DtcInfo(
    title: 'Throttle position sensor implausible',
    meaning: 'The throttle position readings do not agree with each other or with other sensors.',
    severity: Severity.high,
    causes: ['Dirty or faulty throttle body', 'Damaged wiring or connector'],
    driving: 'The car may go into reduced-power (limp) mode. Have it checked soon.',
  ),
  'P0217': const DtcInfo(
    title: 'Engine overheating',
    meaning: 'The engine temperature went above a safe limit.',
    severity: Severity.critical,
    causes: ['Low coolant (leak)', 'Failed cooling fan', 'Failed water pump', 'Stuck thermostat'],
    driving: 'Stop as soon as it is safe and switch off the engine. Driving an overheating engine can destroy it.',
  ),
  'P0234': const DtcInfo(
    title: 'Turbo boost too high',
    meaning: 'The turbocharger is producing more boost pressure than commanded.',
    severity: Severity.high,
    causes: ['Sticking wastegate or wastegate actuator', 'Faulty boost pressure sensor', 'Boost control valve fault'],
    driving: 'Drive gently; the engine may limit power to protect itself. Have it checked soon.',
  ),
  'P0299': const DtcInfo(
    title: 'Turbo boost too low',
    meaning: 'The turbocharger is not producing the boost pressure the engine asked for.',
    severity: Severity.medium,
    causes: [
      'Boost leak (split hose or loose clamp)',
      'Sticking wastegate',
      'Faulty boost control valve',
      'Worn turbo',
    ],
    driving: 'Usually drivable with reduced power. Have it checked soon.',
  ),
  'P0325': const DtcInfo(
    title: 'Knock sensor circuit fault',
    meaning: 'The sensor that listens for engine knock (pinging) is not giving a valid signal.',
    severity: Severity.medium,
    causes: ['Faulty knock sensor', 'Damaged wiring or connector', 'Sensor not tightened correctly'],
    driving: 'Drivable; the engine may run with retarded timing and slightly less power.',
  ),
  'P0335': const DtcInfo(
    title: 'Crankshaft position sensor fault',
    meaning: 'The engine computer cannot read engine speed and position from the crankshaft sensor.',
    severity: Severity.high,
    causes: ['Faulty crankshaft sensor', 'Damaged wiring or connector', 'Damaged sensor reluctor ring'],
    driving: 'The engine may stall or not start. Have it checked as soon as possible.',
  ),
  'P0340': const DtcInfo(
    title: 'Camshaft position sensor fault',
    meaning: 'The engine computer cannot read the camshaft position.',
    severity: Severity.high,
    causes: ['Faulty camshaft sensor', 'Damaged wiring or connector', 'Timing problem'],
    driving: 'Starting may be slow or the engine may run poorly. Have it checked soon.',
  ),
  for (final c in ['P0365', 'P0366', 'P0367', 'P0368'])
    c: const DtcInfo(
      title: 'Camshaft position sensor B fault',
      meaning:
          'The signal from the second camshaft position sensor (bank 1, usually the exhaust camshaft) is '
          'missing or does not fit the crankshaft position. Logged once and not confirmed, it is often a loose '
          'connector or a brief glitch.',
      severity: Severity.medium,
      causes: [
        'Faulty camshaft sensor',
        'Loose, corroded or oily connector',
        'Damaged wiring',
        'Camshaft adjuster or timing chain wear (if it keeps coming back)',
      ],
      driving:
          'Usually fine to drive. If it returns as confirmed, the engine light comes on, or the engine starts '
          'slowly or idles rough, have the sensor and timing checked.',
    ),
  'P0016': const DtcInfo(
    title: 'Crankshaft and camshaft out of sync',
    meaning: 'The crankshaft and camshaft positions do not line up as they should.',
    severity: Severity.high,
    causes: [
      'Stretched timing chain or worn tensioner',
      'Timing belt or chain jumped a tooth',
      'Faulty camshaft adjuster or its control valve',
      'Faulty crankshaft or camshaft sensor',
    ],
    driving:
        'Have it checked as soon as possible: a timing chain or belt problem can lead to serious engine '
        'damage if it fails.',
  ),
  'P0011': const DtcInfo(
    title: 'Camshaft timing too far advanced (bank 1)',
    meaning: 'The intake camshaft is more advanced than commanded.',
    severity: Severity.high,
    causes: ['Faulty camshaft adjuster control valve', 'Low or dirty engine oil', 'Timing chain problem'],
    driving: 'Check the oil level and have it checked soon.',
  ),
  'P0010': const DtcInfo(
    title: 'Camshaft adjuster circuit fault (bank 1)',
    meaning: 'The control circuit of the camshaft adjuster valve has an electrical fault.',
    severity: Severity.medium,
    causes: ['Faulty adjuster control valve', 'Damaged wiring or connector'],
    driving: 'Usually drivable with reduced performance. Have it checked soon.',
  ),
  'P0401': const DtcInfo(
    title: 'Exhaust gas recirculation flow too low',
    meaning: 'Not enough exhaust gas is being fed back into the intake by the EGR system.',
    severity: Severity.medium,
    causes: ['Carbon-clogged EGR valve or passages', 'Faulty EGR valve'],
    driving: 'Usually drivable; may fail an emissions test.',
  ),
  'P0402': const DtcInfo(
    title: 'Exhaust gas recirculation flow too high',
    meaning: 'Too much exhaust gas is being fed back into the intake.',
    severity: Severity.medium,
    causes: ['EGR valve stuck open', 'Faulty EGR control'],
    driving: 'Usually drivable; idle may be rough.',
  ),
  'P0440': const DtcInfo(
    title: 'Fuel vapour system fault',
    meaning: 'The system that captures fuel vapour from the tank has a fault.',
    severity: Severity.low,
    causes: ['Loose or worn fuel cap', 'Leaking vapour hose', 'Faulty purge or vent valve'],
    driving: 'Safe to drive. Check the fuel cap first.',
  ),
  'P0441': const DtcInfo(
    title: 'Fuel vapour purge flow incorrect',
    meaning: 'The purge valve is not letting the right amount of fuel vapour into the engine.',
    severity: Severity.low,
    causes: ['Faulty purge valve', 'Blocked or leaking hose'],
    driving: 'Safe to drive.',
  ),
  'P0442': const DtcInfo(
    title: 'Small fuel vapour leak',
    meaning: 'A small leak was found in the fuel vapour system.',
    severity: Severity.low,
    causes: ['Loose or worn fuel cap seal', 'Small cracked hose', 'Leaking purge valve'],
    driving: 'Safe to drive. Check the fuel cap first.',
  ),
  'P0455': const DtcInfo(
    title: 'Large fuel vapour leak',
    meaning: 'A large leak was found in the fuel vapour system.',
    severity: Severity.low,
    causes: ['Fuel cap missing or not tightened', 'Disconnected or split hose'],
    driving: 'Safe to drive. Check the fuel cap first.',
  ),
  'P0456': const DtcInfo(
    title: 'Very small fuel vapour leak',
    meaning: 'A very small leak was found in the fuel vapour system.',
    severity: Severity.low,
    causes: ['Fuel cap seal', 'Tiny hose crack'],
    driving: 'Safe to drive.',
  ),
  'P0500': const DtcInfo(
    title: 'Vehicle speed signal fault',
    meaning: 'The engine computer is not receiving a valid vehicle speed signal.',
    severity: Severity.medium,
    causes: ['Faulty wheel speed sensor', 'ABS module fault', 'Wiring problem'],
    driving: 'Drivable, but the speedometer, cruise control or gear changes may misbehave.',
  ),
  'P0505': const DtcInfo(
    title: 'Idle speed control fault',
    meaning: 'The engine cannot hold the idle speed it wants.',
    severity: Severity.low,
    causes: ['Dirty throttle body', 'Vacuum leak'],
    driving: 'Drivable; idle may be unstable.',
  ),
  'P0506': const DtcInfo(
    title: 'Idle speed lower than expected',
    meaning: 'The engine idles slower than it should.',
    severity: Severity.low,
    causes: ['Dirty throttle body', 'Restricted air intake'],
    driving: 'Drivable; the engine may stall at idle.',
  ),
  'P0507': const DtcInfo(
    title: 'Idle speed higher than expected',
    meaning: 'The engine idles faster than it should.',
    severity: Severity.low,
    causes: ['Vacuum leak', 'Dirty or faulty throttle body'],
    driving: 'Drivable.',
  ),
  'P0562': const DtcInfo(
    title: 'Battery voltage low',
    meaning: 'The electrical system voltage is lower than it should be.',
    severity: Severity.medium,
    causes: ['Weak battery', 'Failing alternator', 'Loose or corroded battery terminals'],
    driving: 'The car may not restart next time. Have the battery and charging system tested.',
  ),
  'P0563': const DtcInfo(
    title: 'Battery voltage high',
    meaning: 'The electrical system voltage is higher than it should be.',
    severity: Severity.medium,
    causes: ['Faulty alternator voltage regulator'],
    driving: 'Have it checked soon: overcharging can damage the battery and electronics.',
  ),
  'P0700': const DtcInfo(
    title: 'Transmission control module reports a fault',
    meaning:
        'This code only says the gearbox computer has stored its own fault. Read the transmission module '
        '(Modules tab) for the actual code.',
    severity: Severity.medium,
    causes: ['See the transmission module\'s own fault codes'],
    driving: 'Depends on the actual fault; the gearbox may be in limp mode.',
  ),
  'P0730': const DtcInfo(
    title: 'Incorrect gear ratio',
    meaning: 'The gearbox input and output speeds do not match the selected gear, so something is slipping.',
    severity: Severity.high,
    causes: [
      'Low or old transmission fluid',
      'Worn clutch packs or clutch',
      'Faulty shift solenoid',
      'Speed sensor fault',
    ],
    driving: 'Drive gently and have it checked soon to avoid further gearbox damage.',
  ),
  'P0740': const DtcInfo(
    title: 'Torque converter clutch circuit fault',
    meaning: 'The lock-up clutch inside the torque converter has an electrical or control fault.',
    severity: Severity.medium,
    causes: ['Faulty solenoid', 'Wiring problem', 'Low transmission fluid'],
    driving: 'Usually drivable; fuel consumption may rise.',
  ),
  'C0035': const DtcInfo(
    title: 'Left front wheel speed sensor fault',
    meaning: 'The ABS computer is not getting a valid signal from the left front wheel speed sensor.',
    severity: Severity.medium,
    causes: ['Faulty sensor', 'Damaged wiring', 'Dirty or damaged sensor ring on the hub'],
    driving: 'Brakes still work, but ABS and stability control may be off. Drive carefully, especially in the wet.',
  ),
  'C0040': const DtcInfo(
    title: 'Right front wheel speed sensor fault',
    meaning: 'The ABS computer is not getting a valid signal from the right front wheel speed sensor.',
    severity: Severity.medium,
    causes: ['Faulty sensor', 'Damaged wiring', 'Dirty or damaged sensor ring on the hub'],
    driving: 'Brakes still work, but ABS and stability control may be off. Drive carefully.',
  ),
  'U0100': const DtcInfo(
    title: 'No communication with the engine computer',
    meaning: 'A module could not talk to the engine control module over the car\'s network.',
    severity: Severity.high,
    causes: _commCauses,
    driving: _commDriving,
  ),
  'U0101': const DtcInfo(
    title: 'No communication with the gearbox computer',
    meaning: 'A module could not talk to the transmission control module.',
    severity: Severity.medium,
    causes: _commCauses,
    driving: _commDriving,
  ),
  'U0121': const DtcInfo(
    title: 'No communication with the ABS module',
    meaning: 'A module could not talk to the ABS / stability control module.',
    severity: Severity.medium,
    causes: _commCauses,
    driving: _commDriving,
  ),
  'U0140': const DtcInfo(
    title: 'No communication with the body control module',
    meaning: 'A module could not talk to the body control module (central electrics).',
    severity: Severity.medium,
    causes: _commCauses,
    driving: _commDriving,
  ),
  'U0428': const DtcInfo(
    title: 'Implausible data from the steering angle sensor',
    meaning:
        'A module received steering angle information it did not trust. On many cars this follows battery '
        'work, a wheel alignment or a brief network glitch.',
    severity: Severity.low,
    causes: [
      'Steering angle sensor needs calibrating (basic setting) after alignment or battery work',
      'Brief network fault',
      'Faulty steering angle sensor (if it keeps returning with an ESC warning)',
    ],
    driving: 'Fine to drive if no ESC or steering warning lights are on. Clear it and see if it returns.',
  ),
  'U0155': const DtcInfo(
    title: 'No communication with the instrument cluster',
    meaning: 'A module could not talk to the instrument cluster.',
    severity: Severity.low,
    causes: _commCauses,
    driving: 'Often stored after the battery was disconnected. Clear it and see if it returns.',
  ),
  for (final c in ['P0130', 'P0131', 'P0132', 'P0133', 'P0134'])
    c: DtcInfo(
      title: 'Front oxygen sensor fault (bank 1)',
      meaning: 'The oxygen (lambda) sensor before the catalytic converter is not giving a valid or fast enough signal.',
      severity: Severity.medium,
      causes: _o2Causes,
      driving: 'Usually drivable; fuel consumption and emissions may rise.',
    ),
  for (final c in ['P0135', 'P0141', 'P0030', 'P0036'])
    c: const DtcInfo(
      title: 'Oxygen sensor heater fault',
      meaning: 'The heater inside an oxygen (lambda) sensor is not working, so the sensor takes longer to work.',
      severity: Severity.low,
      causes: ['Faulty oxygen sensor (heater element)', 'Blown fuse', 'Damaged wiring'],
      driving: 'Safe to drive; may fail an emissions inspection.',
    ),
};

const _pSubsystems = {
  '0': 'fuel and air metering',
  '1': 'fuel and air metering',
  '2': 'fuel and air metering (injector circuits)',
  '3': 'ignition and misfire detection',
  '4': 'emissions control',
  '5': 'vehicle speed, idle control and auxiliary inputs',
  '6': 'engine computer and output circuits',
  '7': 'transmission',
  '8': 'transmission',
  '9': 'transmission',
  'A': 'hybrid propulsion',
};

/// Explanation for [code]: a specific entry if known, otherwise what the
/// code's structure says about it.
DtcInfo dtcInfo(String code, {Map<String, DtcInfo> specific = const {}}) {
  final known = specific[code.toUpperCase()] ?? _known[code.toUpperCase()];
  if (known != null) return known;
  final c = code.toUpperCase();
  if (c.length < 4) {
    return const DtcInfo(
      title: 'Unknown fault',
      meaning: 'This code could not be interpreted.',
      severity: Severity.medium,
      driving: 'Have it checked if warning lights are on.',
      isGeneric: true,
    );
  }
  final maker = c[1] == '1' || c[1] == '3';
  final whose = maker ? 'manufacturer-specific' : 'standard';
  return switch (c[0]) {
    'P' => DtcInfo(
      title: 'Engine or gearbox fault',
      meaning:
          'A $whose powertrain code, in the ${_pSubsystems[c[2]] ?? 'powertrain'} group. The exact meaning '
          '${maker ? 'is defined by the car maker' : 'is not in the app\'s list yet'}; searching the code together '
          'with your car model usually finds it.',
      severity: Severity.medium,
      driving: 'If the car drives normally and no warning light flashes, it is usually fine to drive to a garage.',
      isGeneric: true,
    ),
    'C' => DtcInfo(
      title: 'Chassis fault',
      meaning: 'A $whose chassis code: brakes, ABS, stability control, steering or suspension.',
      severity: Severity.high,
      driving: 'Brakes and steering may work without their assist systems. Drive carefully and have it checked.',
      isGeneric: true,
    ),
    'B' => DtcInfo(
      title: 'Body electronics fault',
      meaning: 'A $whose body code: airbags, lights, locks, climate, seats or other comfort systems.',
      severity: Severity.medium,
      driving: 'Usually safe to drive. If the airbag warning light is on, have it checked soon.',
      isGeneric: true,
    ),
    'U' => DtcInfo(
      title: 'Network communication fault',
      meaning: 'A $whose network code: modules had trouble talking to each other.',
      severity: Severity.medium,
      causes: _commCauses,
      driving: _commDriving,
      isGeneric: true,
    ),
    _ => const DtcInfo(
      title: 'Unknown fault',
      meaning: 'This code could not be interpreted.',
      severity: Severity.medium,
      driving: 'Have it checked if warning lights are on.',
      isGeneric: true,
    ),
  };
}
