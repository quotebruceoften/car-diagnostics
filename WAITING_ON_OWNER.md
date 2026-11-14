# Waiting on the owner

Things the app's development needs from the car's owner (2013 Golf 7, 1.4 TSI,
Vgate iCar Pro BLE). Ask "what do you need from me?" to get this list. Remove
an item once it is done.

Last updated: 2026-11-14 (app build 23).

## To answer or decide

1. **Module 14 (adaptive suspension) search: yes or no?**
   The app can't find this module; VCDS can. The fix is a read-only search
   that asks each possible address for its part number and matches the one
   VCDS shows (5Q0 907 376).

2. **Which coding settings do you want in plain words?**
   For example needle sweep, auto-lock, comfort indicator flashes, mirror
   folding. Needed to know which module and bytes to look at in step 6.

## To do at the car

3. **Fuel level after a full tank.**
   Fill the tank completely, open Live > Fuel level and report the number.
   About 50 means the engine reports litres; about 100 means percent. On
   2026-11-13 the app showed 21.6 while the gauge was a little under half.

4. **Clear the twelve stored faults, then rescan.**
   Cruise control 287-296, instrument cluster 16777018 and front camera
   327680 are stored, not active (camera overheated on 2026-11-08). Clear
   them (VCDS, or the module's clear-faults option in the app, which is not
   yet tested on a real car), rescan, and report whether any come back.

5. **Install build 21 and send one scan details file.**
   Confirms that all 16 faults now show their names on the phone.

13. **Module explorer results files** (build 23). In Scan car, open a module,
    tap Explore data, run "Thorough" and share the results file. Most useful
    first: 17 Instrument cluster (mileage, fuel level), 19 Gateway (battery
    monitor), 02 Transmission (clutch temperatures), 5F Infotainment
    (software version). Read-only.

14. **First use of build 23 on the car:** does "Clear all faults" clear the
    twelve stored faults, does the boost reading look right against a known
    figure, is an estimated power shown (the 1.4 TSI may not report air
    flow), and are alerts spoken.

15. **Explorer results for modules 09 and 17, "Thorough"** (most wanted).
    The VCDS adaptation lists (docs/golf7-coding/adaptations-*.csv) give
    each setting's name and current value but not where it lives. Matching
    them against the explorer results finds the addresses, which is what
    lets the app show and later change adaptations.

16. **First coding change from the app** (build 25): one harmless cluster
    setting, then report whether it applied or what the app said.

## To send from VCDS

6. **Long Coding Helper screenshots.**
   For each setting chosen in step 2: open the module in VCDS, Coding >
   Long Coding Helper, and screenshot the bytes with those settings. These
   become the named settings for this exact module version. Nothing is
   written to the car from guessed positions.

7. **A new VCDS auto-scan whenever a fault shows only as a number.**
   Importing it teaches the app the name.

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
