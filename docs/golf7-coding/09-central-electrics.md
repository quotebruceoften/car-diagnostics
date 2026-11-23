# 09 Central electrics: long coding notes

Transcribed from VCDS Long Coding Helper photos (2026-11-14). Nothing here
has been written to the car.

- Module: 5Q0 937 085 M, label file 5Q0-937-08X-HV1.CLB, 30 bytes
- Coding: `03001A42424122FB4DE44000000C0728100A000000000000000000000000`

| Byte | Value | Meaning in the helper (set = ticked on this car) |
|---|---|---|
| 0 | 03 | bits 0-1: 00 Left-hand drive (PR-L0L); 03 Right-hand drive (PR-L0R) (current). bits 2-3: 00 Volkswagen (current); 04 Audi; 08 Seat; 0C Skoda |
| 1 | 00 | bit 0 Keyless entry (KESSY) installed; bit 1 Trailer hitch control module installed; bit 4 Roof control module (RP-3FB) installed |
| 2 | 1A | bits 0-2: 00 Halogen headlights w/o Light Assist (PR-8ID+8G0); 02 Bi-Xenon w/o Light Assist (PR-8IG/8IP+8G0) (current); 03 Bi-Xenon with Light Assist (8G1). bit 3 High Traction Drop Downs (HTDD) installed (set); bit 4 Automatic transmission installed (set) |
| 3 | 42 | bit 1 Climate control installed (set). bits 2-4: 00 Seat heating NOT installed (current); 04 Front seat heating installed. bits 5-7: 00 Heated front/rear window NOT installed; 40 Heated rear window installed (current); 60 Heated front and rear window installed |
| 4 | 42 | bit 1 Start-stop/recuperation (PR-7L6) installed (set); bit 6 Ambient temperature sensor installed (set); bit 7 Brake pad wear sensor installed |
| 5 | 41 | bit 0 Operating and display protocol (BAP) active (set); bit 1 Lock/unlock button directly connected to BCM; bit 2 Lock/unlock toggle button installed; bit 6 Rear power windows installed (set); bit 7 Footwell lights installed |
| 6 | 22 | bits 0-1: 00 Light sensor (RP-8N4) NOT installed; 02 Light sensor (PR-8N6) installed (current). bits 5-6: 00 Xenon shutter (PR-8ID/8IT) NOT installed; 20 Xenon shutter (PR-8IG/8IM/8IP) installed (current) |
| 7 | FB | bit 2 Light switch via LIN databus installed; bit 3 Light switch with front fog lights (set); bit 4 with rear fog light(s) (set); bit 5 with Assistance Driving Light (ADL) (set); bit 6 with position lights (set); bit 7 Humidity sensor (PR-9AK) installed (set). Bits 0 and 1 are set but have no label |
| 8 | 4D | bits 0-1 remote control frequency: 00 not installed (PR-5D0); 01 North America 315 MHz (PR-5D2/5D4) (current); 03 Europe/Rest of world 434.42 MHz (PR-5D1); 02 South Korea 433.92 MHz (PR-5D8). bit 2 Personalization profiles active (set); bit 6 Central locking w/o SAFE function installed (set). Bit 3 is set but has no label |
| 9 | E4 | bit 2 Rear lid lock with pre-latch installed (set); bit 6 Door locks w/o SAFE function for North American region installed (set); bit 7 Rear passenger doors installed (set). Bit 5 is set but has no label |
| 10 | 40 | bit 6 Hood switch installed (set) |
| 11 | 00 | bit 2 Rear lid remote button directly connected to BCM; bit 7 Anti-theft system deactivation button directly connected to BCM |
| 12 | 00 | bit 0 Anti-theft system installed/active; bit 1 Anti-theft rear window/glass monitoring installed; bit 4 Alarm horn/sounder installed; bit 5 Inclination sensor installed; bit 6 Start anti-theft alarm delay with mechanical (door lock) opening (Thatcham); bit 7 Interior monitoring installed. None set: no factory alarm |
| 13 | 0C | bit 2 Rear wiper installed (set); bit 3 Headlight washers installed (set); bit 4 Heated front washer jets installed |
| 14 | 07 | bit 0 Coolant level sensor installed (set); bit 1 Brake fluid level sensor installed (set); bit 2 Washer fluid level sensor installed (set) |
| 15 | 28 | bit 3 Start-stop deactivation button installed (set); bit 5 Drive select button installed (set); bit 7 Drive select button w/o function light installed |
| 16 | 10 | bit 2 Auxiliary/parking heater installed; bit 3 Electric steering column lock (ESCL) installed; bit 4 External consumer via terminal 30G installed (set) |
| 17 | 0A | bit 1 Ambient door panel light(s) installed (set); bit 2 Ambient cupholder light(s) installed; bit 3 Ambient footwell light(s) installed (set); bit 4 Ambient speaker light(s) installed |
| 18-19 | 00 00 | no entries in the helper |
| 20-29 | 00 | zeros |

All 30 bytes are transcribed. Every labelled bit describes fitted equipment;
none is a comfort setting, so no named settings are offered for this module's
long coding. Its comfort functions are expected in the adaptation channels.

## Explorer: "The rest" (0x3000-0xEFFF), 2026-11-21

With Thorough (0x0000-0x2FFF, 0xF000-0xFFFF) this covers every data
identifier the module could answer in the default session. Results:
explorer-09-rest.txt. Only 18 answered, and none of them is a comfort setting:

| DIDs | Meaning (read from the values) |
|------|--------------------------------|
| 6001 / 6002 | Serial numbers of two LIN devices attached to the module |
| 6201, 6601 / 6202, 6602 | Part numbers: 5G2955119A (front wiper motor) and 5Q0955547 (rain/light sensor) |
| 6401 / 6402 | Software versions: 0551 and 0042 |
| 6801 / 6802 | Hardware versions: 042 and 024 |
| 6A01 / 6A02 | Serial numbers; the sensor's says it was made 2013-04-02 08:37 |
| 6C01 / 6C02 | System names: "WWS" (wiper system, dated 13-03-16) and "RLFS" (rain/light/humidity sensor) |
| 3800, 3A3B-3A3D | Unknown, unchanged since the earlier sweep |

So the comfort settings in adaptations-09.csv (indicator flashes and so on)
are not readable with a plain read in the default session. Next to try:
the same sweep in the extended diagnostic session (what VCDS uses for
adaptations), still read-only.

The sweep ran in the background with build 39: about 1.3 items/s for the first
1000 items (on screen and off), then the remaining 43,000 items within an hour
in the background, so background mode does not slow it down.

## Explorer: Thorough in deeper mode (extended session), 2026-11-23

Results: explorer-09-deeper.txt (VIN removed). 206 items answered against
122 in the default session. The 85 extra items are all in 04FB-0572,
0D00-0D21 and 1690. The comfort settings are in **0D00-0D21**: matching the
byte counts and values against adaptations-09.csv gives these blocks.
"Sure" means several values line up; nothing here has been written.

| DID | Bytes | VCDS adaptation group | How it matches | |
|-----|-------|----------------------|----------------|---|
| 0D05 | 05 00 20 C8 20 00 A2 03 00 | IDE01268 Windshield wiper (9) | 5 washes per wipe; 2000 ms = C8 x10; 320 ms = 20 x10 | sure |
| 0D06 | 02 0F 06 AA AA 00 00 00 | IDE04927 Window heater (8) | 600 s = 06 x100; 35.0 °C = AA x0.5 - 50 (twice) | sure |
| 0D1D | 02 00 10 00 50 00 00 B4 78 64 C8 BE A0 | IDE03638 Stationary cornering lamp (13) | 180°, 120°, 40 km/h = 50 x0.5, 95/80 °C = BE/A0 x0.5, 100 °C = C8 x0.5 | sure |
| 0D1E | 5E 62 5E 62 94 98 94 98 DA DC DA DC 0A 16 | IDE06089 Seat heater levels (14) | 23.5/24.5/37/38/54.5/55 °C = x0.25; 10 s; 1.10 °C = 16 x0.05 | sure |
| 0D04 | 05 0A 6A 0A 74 | IDE04926 Coming/leaving home (5) | 10 s and 10 s; brightness threshold 116 = 74 | sure |
| 0D1F | 32 32 32 04 | IDE02957 Ambient lighting (4) | three 50 % profile defaults = 32 | sure |
| 0D0C | 01 0D C8 01 | IDE08786 Assistance light functions (4) | AFL delay 2000 ms = C8 x10 | likely |
| 0D21 | 00 00 00 00 | IDE08788 Dynamic turn signal modes (4) | all 17 "not active" | likely |
| 0D20 | 16 77 35 | IDE02711 Rear wiper (3) | interval pauses 7, 7, 3, 5 s as nibbles | likely |
| 0D03 | 00 23 64 00 00 00 | IDE06096 Interior lights (6) | search light 100 % = 64 | likely |
| 0D0D | 65 C0 AC AF 78 03 | IDE08542 Access control 2 (6): comfort closing, mirror fold and dip | window release 600 s = 78 x5 | likely |
| 0D13 | 00 01 00 00 00 | IDE07470 Park light after-run (5) | 1 min | likely |
| 0D01 | 4C 3C 01 00 ... (14) | IDE04924 Driving and parking light (14) | turn light on-time 15 min = 3C x15 s | likely |
| 0D00 | F2 14 19 | IDE04923 Turn signal control (3), incl. comfort flashes = 3 | 10.0 % = 14 x0.5; 0.100 % = 19 x0.004; the flash count is probably in the low bits of F2 | likely |
| 0D08 | 0A B4 00 05 | IDE05142 Access control (4): auto lock/unlock | the remaining 4-byte block | guess |
| 0D14-0D19 | 3C 9B, 0B 32, 02 AA, 0A 7C (2 each) | MAS01471/2, MAS05055/6, IDE01550, IDE07356 wiper positions | angles; pairs repeat | guess |
| 0D02, 0D0E, 0D0F | 00 00, 18 00, 00 00 | IDE06864 Daytime running lamps, IDE02269 Acknowledgement signals, IDE07007 Remote heating (2 each) | DRL and remote all off/zero; 18 = "DELAY" flags | guess |
| 0D07, 0D10, 0D11 | 40, 30, 01 | IDE04928 Anti-theft, IDE08787 Auxiliary functions, IDE06425 Dynamometer (1 each) | | guess |

Other new items:

- **0550-0572** (35 x 16 bytes): one block per lamp output, Leuchte 0-34
  (the ENG116936-ENG116970 groups, each 16 bytes long). **0D0B** (560 bytes)
  is the same 35 blocks in one piece: IDE05145 Light configuration (560).
- **0510-051E** (15 blocks of 6-22 bytes): the interior light dimming curves
  (ENG116831-ENG116980, ENG117284, ENG148505), lengths match one for one.

Next: confirm the bit positions by changing a setting from the radio's
menu (Settings > Lights / Mirrors and wipers / Opening and closing) and
reading 0D00-0D21 before and after. Only after that could the app offer
these as named settings.
