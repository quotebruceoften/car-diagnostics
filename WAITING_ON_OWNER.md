# Waiting on the owner

Things the app's development needs from the car's owner (2013 Golf 7, 1.4 TSI,
Vgate iCar Pro BLE). Ask "what do you need from me?" to get this list. Remove
an item once it is done.

Last updated: 2026-11-25 (app build 43). Coding from the app is verified on the cluster.

To send results: Overview > Tools > Send to developer (or Settings > Your data).

## The one VCDS session

Everything the app still needs from VCDS, in one sitting, so the app can
stand alone afterwards. About 1.5-2 hours with the ignition on, engine off.
Connect a battery charger if you have one. The car has one diagnostic port,
so swap between the VCDS cable and the Vgate where a step says so. Save
every VCDS file (they go to C:\Ross-Tech\VCDS\Logs or \Scans) and send them
all at the end.

**A. Auto-Scan (10 min, VCDS).** Auto-Scan > all modules > Save.
   - Names every stored fault, including engine fault 4629 that the app
     shows only as a number.
   - Shows whether module 14 (adaptive suspension) exists and at which
     address (the app can't find it).
   - Gives the gateway's installation list and every module's coding.
   - Afterwards: in the app, Import VCDS scan, so the names are learned.

**B. Long Coding Helper, remaining modules (30 min, VCDS).** For each
   module below: open it > Coding > Long Coding Helper, and screenshot every
   byte (as you did for 09, 17 and 5F). These become the plain-word
   settings in the app.
   - 08 Climate, 13 Adaptive cruise, 16 Steering wheel, 19 Gateway,
     42 Driver door, 52 Passenger door, 55 Headlight range, A5 Front camera.
   - Skip 01 Engine, 02 Gearbox, 03 ABS, 15 Airbags and 44 Steering assist:
     the app will not offer coding changes on those for safety.

**C. Adaptation lists, remaining modules (15 min, VCDS).** For each module:
   Adaptation > Save (the same CSV export you sent for 09 and 17).
   - 5F Infotainment, 08, 13, 16, 19, 42, 52, 55, A5.

**D. The adaptation changes you actually want (20 min, VCDS + app).**
   Each change both gives you the feature and shows the app how it is
   stored. The "before" sweep already exists (2026-11-23).
   1. VCDS: 09 > Adaptation > "Turn signal control-Komfortblinken
      Blinkzyklen" 3 > 4 (or another number you prefer). Save.
   2. **Write down whether VCDS asked for a login / security access code**
      before saving, and which code it used. This decides whether the app
      can make adaptation changes on its own.
   3. Swap to the Vgate. App: Scan car > Central electrics > Explore data >
      "Settings" > Start. Share the file.
   4. Repeat 1-3 for up to five other 09 settings you want, one at a time,
      with an app "Settings" sweep after each. Write down each change
      (name, old value, new value). Ideas from your car's list: horn chirp
      when locking ("Akustische Rueckmeldung verriegeln"), comfort opening
      with the key ("Access control 2-Comfort opening"), daytime running
      lights options, coming home lights, rear wiper when reversing.
   Change values back afterwards only if you don't want them.

**E. Fuel level (5 min, VCDS + app).**
   1. VCDS: 17 Instruments > Advanced Measuring Values > tick the fuel level
      values (litres and sensor). Screenshot them.
   2. Swap to the Vgate straight away. App: Live > note "Fuel level"; then
      Scan car > Instrument cluster > Explore data > "Quick" > Start.
      Share the file.
   Matching the litres against the sweep finds the real fuel value, so the
   fill-up test is no longer needed.

**Not needed from VCDS any more:** coding writes (the app does these), the
service reset (the app does this; still to be tried after your next
service), explorer sweeps, fault reading and clearing.

**What stays outside the app afterwards:** a fault the app has never seen
shows as a VW number until it is named (from a later VCDS scan or public
sources), and settings that need a login code if step D2 says so.

## To do at the car

1. **First service indicator reset** (after your next service): Service log >
   "Reset service indicator". Report the message, and whether the dashboard
   shows the new interval after ignition off/on.

## To report if it happens

8. **A service reminder notification that does not appear**, or appears at
   the wrong time. Notifications have not been tested on a real phone.

9. **An imported VCDS scan that does not name a fault** the log contains.
   That learning step is not covered by the automated tests.

10. **Anything on the Live tab that disagrees with the dashboard** (speed,
    coolant temperature), and the trip computer's fuel use compared with the
    pump after a tank.

11. **Battery test, performance timer and trip computer results** from the
    first real use: none has been tried on the car yet.

12. **Faults that return**: the camshaft sensor code (P0366) and the
    passenger mirror heater (B11F8) were present on 2026-10-29 and gone on
    2026-11-13.

## Optional, later

- A Google Play developer account ($25, in the owner's name) if the app
  should be installable from the Play Store.
- The SM2 Pro adapter, other car makes and other languages are on the
  roadmap and need nothing yet.
