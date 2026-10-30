# Car Diagnostics (mobile app)

A Flutter app for Android and iOS that reads fault codes and live data from
any OBD-II car. It also has full module diagnostics and long coding for
Volkswagen Group cars (VW, Audi, Škoda, SEAT, Cupra).

## Features

- **Connect** to a Bluetooth LE or Wi-Fi ELM327 adapter, or to a built-in
  demo car (a simulated VW Golf) so you can try every screen without a car.
  The app remembers your adapter and reconnects automatically when it opens.
- **Your car:** the car's name and year from the VIN (for example "Volkswagen Golf 7 · 2013")
  over your own photo, or a short muted video loop, taken in the app or picked from your gallery.
  Pictures are stored on the phone, one per car. After a module scan, chips for the engine,
  chassis, interior and lights turn green or red; tap one to see that area's modules.
- **Overview:** check engine light, number of stored codes, battery voltage, coolant temperature,
  and an **inspection readiness** check (which emissions self-tests have finished).
- **Faults:** stored, pending and permanent emissions codes with
  descriptions and clearing codes. Tap a code for a plain-language page:
  what it means, how serious it is, common causes, whether it's safe to drive and, for engine
  codes, the **freeze frame** (speed, load, temperature when it was stored) explained in words.
- **Live data:** pick sensors and watch them update, with a small chart for
  each one. Tap a sensor for a full graph (30 s to 10 min) with lowest, highest and average.
  **Alerts** vibrate and show a red bar when a value crosses a limit you set (for example
  coolant above 110 °C). The **driving dashboard** shows four large dials in landscape and can
  record a drive to a CSV file.
- **Battery test:** battery voltage at rest, the dip while the engine starts, and the charging
  voltage, each with a verdict.
- **Trip computer:** live fuel consumption (from fuel rate, or from air flow on petrol
  engines), distance, average economy and the cost of each drive.
- **Performance timer:** 0–100 km/h, 80–120 km/h and 100–0 km/h (or mph equivalents), started
  and stopped automatically from the car's speed, with braking distance.
- **Service log:** record services and get reminders by date or distance, including phone
  notifications a week before and on the day. Works without the adapter; cars that report their
  odometer over OBD update the mileage automatically.
- **Scan history and reports:** every module scan is saved per car, with new and fixed faults
  compared to the previous scan. Any scan can be shared as a PDF report. **Fault trends** show
  which faults keep coming back ("in 3 of 4 scans since March") and which have gone.
- **VCDS import:** add a VCDS auto-scan log (.txt) to the scan history, from the scan history or
  from the first screen without connecting. Its mileage updates the service log.
- **Settings:** °C/°F, km/miles, fuel economy unit, fuel price, light/dark/automatic theme,
  automatic reconnect, and **backup and restore** of all app data in one file.
- **Modules (VW Group):** scan every module (engine, transmission, ABS,
  airbags, central electrics, instrument cluster, gateway, …). See each
  module's part number, software version and fault codes, and clear them.
- **Coding tab (VW Group):** lists every module that can be coded, shows which ones have named
  options, and keeps the backups for this car in one place.
- **Long coding (VW Group):**
  - A byte and bit editor that works on any module.
  - Named options (switches, dropdowns) when a coding profile matches the
    module's part number.
  - Every write is backed up first, then read back to confirm it took.
  - Backups can be loaded back into the editor and written again.

## Supported adapters

| Adapter | Android | iPhone |
| --- | --- | --- |
| Bluetooth LE / "BLE 4.0" ELM327 (Vgate iCar Pro BLE, vLinker, many clones) | ✅ | ✅ |
| Wi-Fi ELM327 | ✅ | ✅ |
| Classic Bluetooth ELM327 (pairs in system settings) | not yet | ❌ never works on iPhone |
| Brand-locked adapters made for one app (e.g. Carly) | usually ❌ | usually ❌ |

If an adapter connects but doesn't answer like an ELM327, the app says so.

The car must use CAN (ISO 15765-4). That covers US cars from model year 2008
and most European cars from about 2006, including every UDS-era VW.

## Get the Android app

GitHub builds the app on every push (see `.github/workflows/build.yml`) and
publishes it as the **Latest build** release, so the download link never
changes:

`https://github.com/<owner>/<repo>/releases/download/latest-build/car-diagnostics.apk`

Open that link on your Android phone and install the file. Android asks you
to allow installing from that source the first time.

### Stable signing (so updates install over the old version)

Android only installs an update over an existing app if both are signed with
the same key. Add these two repository secrets once (GitHub: **Settings →
Secrets and variables → Actions → New repository secret**):

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The keystore file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Its password (the key alias is `cardiag`) |

To make your own key: `keytool -genkeypair -keystore release.jks -storetype PKCS12
-alias cardiag -keyalg RSA -keysize 2048 -validity 10000`, then `base64 -w0
release.jks`. Keep the keystore safe: losing it means users have to uninstall
to get updates. Without the secrets, builds fall back to a debug key that may
differ between builds.

iPhone builds need a Mac with Xcode and an Apple developer account.

## Run it

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.35 or newer).

```bash
cd mobile
flutter pub get
flutter run            # with a phone connected or an emulator running
```

```bash
flutter test           # unit and widget tests, no device needed
```

```bash
flutter build apk      # Android installable
```

For iOS you also need a Mac with Xcode. Run `flutter build ios` there, or
open `ios/Runner.xcworkspace` and set your signing team.

Long-press **Demo car** on the connect screen to run the demo through an
emulated ELM327 adapter instead of directly. That uses the real adapter
driver, which is handy when working on it.

## How it's organised

```
lib/
  core/                 Car-independent diagnostics library (pure Dart)
    transport/          ELM327 driver, ISO-TP, Wi-Fi channel
    obd/                OBD-II: PIDs, fault codes
    uds/                UDS (ISO 14229): sessions, data IDs, fault codes, security access
    coding/             Coding profiles, backups, write-and-verify
  brands/               Everything make-specific
    brand.dart          The Brand interface
    vag.dart            Volkswagen Group
    generic.dart        Fallback for other makes
    registry.dart       List of brands + VIN detection
    scanner.dart        Module scan
  platform/             Bluetooth LE channel (needs Flutter plugins)
  sim/                  Simulated VW Golf + ELM327 emulator (demo mode and tests)
  ui/                   Screens
assets/profiles/        Coding profiles (JSON)
```

`core/` has no Flutter dependency. It mirrors the Python `cardiag` library in
the repository root, and the two share the coding profile format.

## Adding another make

All make-specific knowledge sits behind `Brand` (`lib/brands/brand.dart`). To
add a make:

1. Create `lib/brands/<make>.dart` with a class that extends `Brand`:
   - `wmiPrefixes`: the first three VIN characters this make uses. The app
     uses them to detect the car.
   - `modules`: each module's name and CAN request/response IDs.
   - Optionally `identificationDids`, `codingDid`, `codingAccessFor()` (the
     diagnostic session and security access needed to write), `describeDtc()`
     for make-specific code descriptions, and `explainError()` for helpful
     hints.
2. Add it to `supportedBrands` in `lib/brands/registry.dart`.
3. If the make needs a seed/key algorithm to unlock writes, register it with
   `registerSecurityAlgorithm()` (`lib/core/coding/security.dart`).
4. Add coding profiles under `assets/profiles/` and list them in the brand's
   `profileAssets`.
5. To get demo mode and tests, add a simulated car for the make in
   `lib/sim/vehicle.dart`.

The screens, scanner, coding editor and backups work unchanged.

## Coding profiles

A profile maps a module's coding bytes to named options. It's the same JSON
format as the command-line tool, plus three optional fields that decide
which module the profile applies to:

```json
{
  "id": "vag_09_5Q0937084",
  "name": "Central electrics",
  "brand": "vag",
  "module": "09",
  "part_numbers": ["5Q0937084"],
  "tx_id": "0x70E", "rx_id": "0x778",
  "did": "0x0600", "length": 30,
  "options": [
    {"key": "drl", "label": "Daytime running lights", "byte": 0, "bit": 0, "type": "bool"}
  ]
}
```

`assets/profiles/vag_09_demo.json` only matches the demo car. **Real VW
coding layouts depend on the module's part number and software version.**
Only add a profile for a real module once you've confirmed its layout,
for example by comparing coding before and after a known change.

See [ROADMAP.md](../ROADMAP.md) for planned work.

## Safety and limits

- Coding changes how the car behaves. The app backs up before every write and
  verifies the result, but a wrong value can still disable features or
  modules. Keep the ignition on, use a battery charger for longer sessions,
  and don't change bits you don't understand.
- **SFD (2020+ VW Group cars):** on cars like the Golf 8 and the ID. models,
  many modules are locked and must be unlocked online through VW before they
  accept coding. The app can't do this. When a write is refused, it says
  that SFD may be the reason.
- Some modules need a security access login before they accept coding. The
  app has the mechanism (`CodingAccess`, security algorithm registry) but
  includes no manufacturer algorithms.
- Adaptations, output tests and basic settings are not implemented yet.
- Clearing emissions codes resets the readiness monitors, so the car can fail
  an inspection until it has been driven enough.
