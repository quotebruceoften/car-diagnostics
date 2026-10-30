/// Volkswagen Group meanings of manufacturer-specific fault codes. Body (B)
/// and some network (U) codes mean different things on different makes, so
/// these only apply to VW Group cars. Titles follow the module's own fault
/// text as shown by VW diagnostic tools.
library;

import '../core/obd/dtc_info.dart';

const vagDtcs = <String, DtcInfo>{
  'U1123': DtcInfo(
    title: 'Data bus: error message received',
    meaning:
        'This module received a message from another module saying that one of its own functions has a '
        'fault. It is a side effect: the real fault is stored in another module.',
    severity: Severity.low,
    causes: ['A fault stored in another module', 'Low battery voltage during starting'],
    driving: 'Fine to drive. Deal with the other modules\' faults, then clear this one.',
  ),
  'B1263': DtcInfo(
    title: 'Fuel tank flap control circuit fault',
    meaning:
        'The central electrics module found an electrical fault in the motor that locks and unlocks the fuel '
        'filler door with the central locking.',
    severity: Severity.low,
    causes: [
      'Faulty fuel flap locking actuator (behind the filler door)',
      'Damaged wiring or corroded connector at the actuator',
    ],
    driving:
        'Safe to drive. If the filler door stays locked, there is usually a manual release cord behind a '
        'cover in the boot, on the side of the filler door.',
  ),
  'B11F3': DtcInfo(
    title: 'Mirror adjustment switch: signal implausible',
    meaning:
        'The driver door module received an odd signal from the switch that moves and selects the door '
        'mirrors.',
    severity: Severity.low,
    causes: ['Worn or dirty mirror adjustment switch', 'Moisture in the switch', 'Loose connector behind the switch'],
    driving: 'Safe to drive. If the mirrors move on their own or not at all, replace the switch (a common part).',
  ),
  'B11F8': DtcInfo(
    title: 'Heated exterior mirror: open or short to ground',
    meaning:
        'The passenger door module found a broken circuit in the mirror heating, so that mirror will not '
        'clear mist or ice.',
    severity: Severity.low,
    causes: [
      'Failed heating element in the mirror glass (it is built into the glass)',
      'Loose connector behind the mirror glass',
      'Damaged wiring in the door hinge area',
    ],
    driving: 'Safe to drive. Replace the mirror glass (it comes with the heater) or check its two small connectors.',
  ),
  'B1065': DtcInfo(
    title: 'Rear left bass speaker: open circuit',
    meaning: 'The radio sees no speaker connected on its rear left bass output.',
    severity: Severity.low,
    causes: [
      'Speaker disconnected or failed',
      'Broken wire in the door hinge area',
      'Loose radio connector (if several speakers report it at once)',
    ],
    driving:
        'Safe to drive. If both rear speakers report it at the same moment, check the radio connector and '
        'wiring before replacing speakers.',
  ),
  'B1067': DtcInfo(
    title: 'Rear right bass speaker: open circuit',
    meaning: 'The radio sees no speaker connected on its rear right bass output.',
    severity: Severity.low,
    causes: [
      'Speaker disconnected or failed',
      'Broken wire in the door hinge area',
      'Loose radio connector (if several speakers report it at once)',
    ],
    driving:
        'Safe to drive. If both rear speakers report it at the same moment, check the radio connector and '
        'wiring before replacing speakers.',
  ),
};
