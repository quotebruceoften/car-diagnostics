# 17 Instrument cluster: long coding notes

Transcribed from VCDS Long Coding Helper photos (2026-11-14). Nothing here
has been written to the car.

- Module: 5G0 920 861 B, label file 5G0-920-XXX-17.CLB-SRI3, 15 bytes
- Coding: `27A419087F80000E01882A03040000`

| Byte | Value | Meaning in the helper (set = ticked on this car) |
|---|---|---|
| 0 | 27 | bit 0 Scale illumination (terminal 15 on and 58 off) active (set); bit 1 Needle illumination (same) active (set); bits 2-4 seat belt warning: 00 inactive; 04 RoW Euro NCAP (current); 08 North America; 0C RoW Euro NCAP2; 10 RoW Euro NCAP2 escalated; bit 5 Right-hand drive (set); bit 6 Speed warning at 120 km/h (75 mph) active |
| 1 | A4 | bit 0 Gauge test/needle sweep (staging) active; bit 2 Driver information system (DIS) active (set); bit 3 Lap timer active; bit 4 Key ignition warning active; bit 5 Cruise control system installed (set); bit 7 Efficiency program for board computer active (set) |
| 2 | 19 | bits 0-2 fuel tank: 00 Variant 1; 01 Variant 2 (current); 02-07 Variants 3-8. bits 3-6 model: 18 Variant 3 (current); 20 Variant 4 ... 60 Variant C. bit 7 Wheel speed error counter active |
| 3 | 08 | bits 0-2 tire circumference: 00 Standard (current); 01-07 Variants 2-8. bit 3 Automatic transmission installed (set); bit 4 Electrical steering column lock module installed; bit 7 Direct TPMS installed |
| 4 | 7F | bit 0 Indirect TPMS (set); bit 1 Electro-mechanical parking brake (set); bit 2 ACC (set); bit 3 Headlight levelling (set); bit 4 Adaptive chassis control DCC (set); bit 5 Electro-mechanical power steering (set); bit 6 Lane maintenance assist (set); bit 7 All-wheel drive |
| 5 | 80 | bit 2 Traffic sign recognition installed; bit 3 Lane change assist installed; bit 4 Park/steer assist installed; bit 7 Audio system/display installed (set) |
| 6 | 00 | bit 0 temperature 0 Celsius / 1 Fahrenheit; bit 1 distance 0 km / 1 miles; bit 2 speed 0 km/h / 1 mph; bits 3-4 pressure: 00 bar, 08 PSI, 10 kPa; bits 5-6 fuel volume: 00 litre, 20 gallons (UK), 40 gallons (US); bit 7 time 0 24h / 1 12h |
| 7 | 0E | bits 0-1 date: 00 dd/mm/yyyy, 01 mm/dd/yyyy, 02 yyyy/mm/dd (current); bits 2-3 fuel consumption: 00 mpg (UK), 04 mpg (US), 08 l/100km, 0C km/l (current) |
| 8 | 01 | display language: 01 English (GB) (current); 02 English (North America); 03 French; 04 Italian; 05 Spanish; 06 Portuguese; 07 Polish; 08 Czech; 09 Hungarian; 0A Danish; list continues off-screen |
| 9 | 88 | bits 0-2 start screen: 00 Standard (current); 01-07 Versions 2-8; bit 3 Compass display position bottom instead of top (set); bit 7 Stopping distance reduction / City emergency brake assist installed (set) |
| 10 | 2A | bit 1 Display 'Oil temperature' (set); bit 2 Display 'Acceleration'; bit 3 Display 'Ambient temperature' (set); bit 4 Display 'Volume to be replenished'; bit 5 Display 'Telephone' menu (set); bit 6 Display 'Navigation/Compass'; bit 7 Favorites/Joker button for board computer installed |
| 11 | 03 | bit 0 Stopping distance reduction information (BAP) installed/active (set); bit 1 Lane maintenance assist information (BAP) (set); bit 2 TPMS information (BAP); bit 3 Lane change assist information (BAP) |
| 12 | 04 | bit 0 Noise/sound actuator installed; bit 2 Alternative dimming function active (set) |
| 13-14 | 00 00 | not photographed |

Offered in the app (assets/profiles/vag_17_5g0920861b.json): needle sweep,
lap timer, 120 km/h speed warning, display units, date format, start screen,
compass position, and the oil temperature, acceleration and refuel volume
pages. Not offered: seat belt warning (safety), and the
equipment, fuel tank, model and tyre bytes.

## Writing coding to this cluster (verified 2026-11-15)

Needle sweep was switched on from the app (build 30) and confirmed on the
car. The sequence the cluster accepts:

1. Extended session (0x10 03).
2. Read the stored workshop code from 0xF1A5 (0xF198 is not readable).
3. Write it to 0xF198 (6 bytes). Writing it back to 0xF1A5 is refused
   with NRC 0x31; skipping this step makes the coding write fail with
   NRC 0x24.
4. Write today's date to 0xF199 (3 bytes BCD).
5. Write the coding to 0x0600 and read it back to verify.

No security access (login code) was needed for the coding.

## Service indicator (found 2026-11-15, reset not yet verified on the car)

Matched between the module explorer and the VCDS adaptation list:

| DID | Value then | VCDS adaptation |
|---|---|---|
| 0x2203 | 144873 | Mileage |
| 0x2243 | 10300 (3 bytes) | FIX/ESI: distance since last inspection |
| 0x2244 | 256 (2 bytes) | FIX/ESI: time since last inspection (days) |

The app's "Reset service indicator" writes 0 to 0x2243 and 0x2244 after the
workshop code step above, then reads them back.
