# Roadmap

Planned work, roughly in priority order. Nothing here is scheduled yet.

## Mobile app

- **Test on a real Golf 7** with a Bluetooth LE ELM327 adapter (Vgate iCar Pro BLE) and fix what comes up.
- **Coding profiles for real modules.** Add named options for verified VW part numbers, starting with the
  Golf 7 central electrics (09) and instrument cluster (17).
- **Classic Bluetooth adapters on Android.** Many cheap ELM327 adapters only do classic Bluetooth (SPP).
- **Adaptations, output tests and basic settings** for VW Group modules.
- **More makes.** Each make is one file under `mobile/lib/brands/` (see `mobile/README.md`).

## Laptop tool (`cardiag`, Python)

- **J2534 pass-thru support (SM2 Pro).** Add a `J2534Transport` that loads the vendor's J2534 DLL on
  Windows (PassThruOpen / PassThruConnect with ISO 15765, flow-control filters, PassThruWriteMsgs /
  PassThruReadMsgs). It would give the command-line tool a USB interface that's more reliable than
  Bluetooth for module scans and coding. Hardware testing needs a Windows laptop with the SM2 Pro
  driver installed. Start with read-only commands (VIN, fault codes, module scan) before enabling
  coding writes.
