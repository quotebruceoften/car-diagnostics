# 5F Infotainment: long coding notes

Transcribed from VCDS Long Coding Helper photos (2026-11-14). Source for a
future named-settings profile; nothing here has been written to the car.

- Module: 5G0 035 832, label file 5G0-035-MIB-STD1.CLB, 25 bytes
- Coding: `02730000FF00000011330001001000001F0100960100010001`

| Byte | Value | Meaning in the helper |
|---|---|---|
| 0-2 | 02 73 00 | Model: VW Golf (5G1) [PR-7LG+K8G]. Others: 000000 not coded; 027370 e-Golf (BE1); 027309 Golf Sportsvan (AM1); 027302 Golf Variant (BA5/BX5) |
| 3 | 00 | 00 Navigation function NOT active/installed [PR-7Q0]; 01 Navigation database Europe; 02 North American region |
| 4-7 | FF 00 00 00 | FF000000 4 channels / 8 passive speakers installed [PR-8RM]; 00000000 Sound system with subwoofer installed [PR-8RU]. No other choice in the helper |
| 8 | 11 | bit 0 Microphone 1 connected (set); bit 4 AUX-IN connection active (set); bit 5 Audi Music Interface active/installed |
| 9 | 33 | bits 0-3 FM tuner market: 0 not coded; 1 Europe (EU/CN/AUS/SA, 87.5-108.0 MHz @ 100 kHz) [PR-ER1]; 2 North America [PR-ER3]; current value 3 is not in the helper. bits 4-7 AM tuner market: 00 not coded; 10 Rest of world (531-1602 kHz @ 9 kHz) [PR-ER1]; 20 North America [PR-ER3]; current value 30 is not in the helper |
| 10 | 00 | bits 0-3: 00 DAB tuner band 1 inactive; bits 4-7: 00 DAB tuner band 2 inactive |
| 11 | 01 | bits 0-7: 01 Internal sound system active [PR-8RE/8RH/8RL/8RM]; 02 External sound system active/installed [PR-8RU]; 03 External sound system active/installed [PR-9VE] |
| 12 | 00 | bits 0-3: 00 Antenna for AM/FM (diversity) installed [PR-8ZH] |
| 13 | 10 | bit 3 Radio Text Plus active [STANDARD]; bit 4 PI Ignore active (set); bits 5-6 Broadcast Website Service: 00 not active, 20 restricted, 40 unrestricted, 60 restricted/unrestricted; bit 7 DAB alarm announcement active [PR-QV3] |
| 14 | 00 | not in use |
| 15 | 00 | bit 0 Telephone baseplate installed; bit 1 Telephone antenna baseplate installed |
| 16 | 1F | bit 0 Telephone/Bluetooth available; bit 1 Bluetooth multimedia function; bit 2 Bluetooth function; bit 3 Bluetooth audio function (all set); bits 4-5: 10 Internal Bluetooth automatically visible [STANDARD] |
| 17 | 01 | bits 0-7: 00 None/Not supported; 01 Highline [PR-A8B/A8C/A8F]; 02 Top-Sport (GTI/GTD/R) |
| 18 | 00 | bits 0-7: 00 None/Standard; 02 GTD; 03 GTI; 06 R-Line; 09 Hybrid |
| 19 | 96 | bit 1 Right-hand drive (set); bit 2 Feature band switching active [STANDARD] (set); bit 4 Rear view camera Low installed (set); bit 5 MOST databus for external amplifier installed; bits 6-7: 80 USB configuration: USB functionality [PR-UE4] |
| 20 | 01 | bit 0 Display 1 installed/connected (set) |
| 21 | 00 | not in use |
| 22 | 01 | bit 0 Instrument cluster graphics [STANDARD] (set) |
| 23 | 00 | bit 0 Speller function active; bit 2 Legal disclaimer active |
| 24 | 01 | bit 0 Emergency call active/installed (set); bit 1 Speech dialog system; bit 2 Navigation function; bit 4 Multimedia import (copy); bit 5 Multimedia import (ripping); bit 6 Traffic sign display; bit 7 Predictive route data |

All 25 bytes are now transcribed. Bytes 17 and 18 are offered in the app as
named settings (assets/profiles/vag_5f_mib_std1_5g0035832.json); the rest
describe fitted equipment and are deliberately not offered.
