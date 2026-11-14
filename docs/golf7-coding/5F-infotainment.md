# 5F Infotainment: long coding notes

Transcribed from VCDS Long Coding Helper photos (2026-11-14). Source for a
future named-settings profile; nothing here has been written to the car.

- Module: 5G0 035 832, label file 5G0-035-MIB-STD1.CLB, 25 bytes
- Coding: `02730000FF00000011330001001000001F0100960100010001`

| Byte | Value | Meaning in the helper |
|---|---|---|
| 0-3 | 02 73 00 00 | not photographed yet |
| 4 | FF | not photographed yet (bytes 5-7 refer to it) |
| 5-7 | 00 00 00 | "Coding details for this byte can be found in byte 04" |
| 8 | 11 | bit 0 Microphone 1 connected (set); bit 4 AUX-IN connection active (set); bit 5 Audi Music Interface active/installed |
| 9 | 33 | bits 0-3 and bits 4-7: helper says "None found" for the current values |
| 10 | 00 | bits 0-3: 00 DAB tuner band 1 inactive; bits 4-7: 00 DAB tuner band 2 inactive |
| 11 | 01 | bits 0-7: 01 Internal sound system active [PR-8RE/8RH/8RL/8RM] (other choices not photographed) |
| 12 | 00 | bits 0-3: 00 Antenna for AM/FM (diversity) installed [PR-8ZH] |
| 13 | 10 | photo unreadable |
| 14 | 00 | not in use |
| 15 | 00 | bit 0 Telephone baseplate installed; bit 1 Telephone antenna baseplate installed |
| 16 | 1F | bit 0 Telephone/Bluetooth available; bit 1 Bluetooth multimedia function; bit 2 Bluetooth function; bit 3 Bluetooth audio function (all set); bits 4-5: 10 Internal Bluetooth automatically visible [STANDARD] |
| 17 | 01 | bits 0-7: 01 User interface skin: Highline (other choices not photographed) |
| 18 | 00 | bits 0-7: 00 Startup screen: None/Standard (other choices not photographed) |
| 19 | 96 | bit 1 Right-hand drive (set); bit 2 Feature band switching active [STANDARD] (set); bit 4 Rear view camera Low installed (set); bit 5 MOST databus for external amplifier installed; bits 6-7: 80 USB configuration: USB functionality [PR-UE4] |
| 20 | 01 | bit 0 Display 1 installed/connected (set) |
| 21 | 00 | not in use |
| 22 | 01 | bit 0 Instrument cluster graphics [STANDARD] (set) |
| 23 | 00 | bit 0 Speller function active; bit 2 Legal disclaimer active |
| 24 | 01 | bit 0 Emergency call active/installed (set); bit 1 Speech dialog system; bit 2 Navigation function; bit 4 Multimedia import (copy); bit 5 Multimedia import (ripping); bit 6 Traffic sign display; bit 7 Predictive route data |

Still needed: bytes 0-4, byte 13, and the open drop-down lists of bytes 9,
11, 17 and 18.
