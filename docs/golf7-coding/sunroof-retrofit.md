# Sunroof retrofit (owner's car, 2026-11)

Parts fitted: factory Golf 7 sunroof with Webasto motor/control unit J245
**8V3 959 591 A** (label "VW370/AU37x", HW H03, PS73.404), switch E325
**5GG 959 613** mounted in an aftermarket LED dome light housing.

## What sources say (forums.ross-tech.com)

From a Golf 7 pan-roof retrofit wired from the factory diagram (thread 7477,
https://forums.ross-tech.com/index.php?threads/7477/):

- Wiring diagram legend: E325 sunroof button, J245 sunroof control unit,
  J519 BCM, **SC24 fuse 24 on fuse holder C**, T5an 5-pin connector,
  T6cp / T6cr 6-pin black connectors, T10le 10-pin, T73a / T73c BCM
  connectors, TH roof coupling point, V1 motor, **earth point 638 on the
  right A-pillar**, A19 / A116 terminal 58d (switch lighting), **B528 LIN
  bus connection** in the main harness.
- "Only 4 wires": power, earth, and two to the central electrics.
- J245 shows in VCDS as a **LIN subsystem of 09** (not its own address).
- BCM long coding **byte 1 bit 4** (roof control module) must be set.
- BCM adaptations used: SAD Komfort oeffnen active, SAD Richtung
  Komfortoeffnen tilting, SAD Komfort schliessen active, FH SAD Kl15Aus
  Freigabezeit 600 s.
- J245 codings seen on Golf 7s: 181801 (8V3 959 591) and **181901 on an
  8V3 959 591 A**.
- E325 is drawn with a transistor symbol: it has electronics, so bridging
  J245 pins to imitate it is not advised.

From a Golf 7 GTI sunroof fault thread (24124,
https://forums.ross-tech.com/index.php?threads/24124/):

- E325 connects with a **5-pin connector back to the sunroof module**
  (not to the BCM). Pin 5 is the switch lighting; pin 4 (brown) is likely
  earth; pins 1-3 carry the switch positions (the poster's reading of his
  diagram, not confirmed).
- A J245 without calibration logs B13C6 54 "Missing calibration / basic
  setting"; a switch problem logs B13C4 29 "Switch for sunroof: signal
  implausible".

## Not found yet

Pin numbers on J245's connectors, SC24's rating, and which J519 pin
carries the LIN line. These need the factory wiring diagram (erWin) or
photos of the connectors with their moulded pin numbers.

## Check with the app

The 09 explorer already lists the BCM's LIN subsystems (6001/6201 wiper
motor, 6002/6202 rain/light sensor). Once J245 is on the LIN line and
byte 1 bit 4 is set, a third entry with 8V3 959 591 A should appear in
the same block.
