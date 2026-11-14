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
