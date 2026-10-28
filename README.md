# cardiag

A car diagnostics and ECU coding tool for the command line. It works with
cheap ELM327 adapters (USB, Bluetooth or Wi-Fi) and includes a simulated
vehicle, so you can try every feature without a car.

- **OBD-II (SAE J1979):** VIN, MIL status, supported PIDs, live data with CSV
  logging, stored/pending/permanent trouble codes, freeze frames, clearing codes.
- **UDS (ISO 14229):** module scan, identification (part numbers, software
  versions), per-module DTCs with status flags, read DIDs, raw requests.
- **Coding:** decode a module's coding block into named options and change
  them. Every write saves a backup first, unlocks the module, then reads the
  value back to verify it. Backups can be restored.

## Install

```bash
pip install .
```

Python 3.10+ is required. `pyserial` is installed automatically.

## Quick start (simulator)

Without `--port`, cardiag uses the built-in simulated car:

```bash
cardiag info
cardiag dtc --all
cardiag live rpm speed coolant_temp --csv drive.csv
cardiag uds scan
cardiag coding show demo_bcm
cardiag coding set demo_bcm drl=off comfort_blinks=5 --dry-run
```

Each command starts a fresh simulated car, so coding changes don't carry over
between runs.

## With a real car

Plug the adapter into the OBD port (under the dashboard), turn the ignition
on, and pass the port:

```bash
cardiag --port /dev/ttyUSB0 info                    # Linux USB
cardiag --port COM3 dtc                             # Windows
cardiag --port /dev/rfcomm0 live                    # Linux Bluetooth (after pairing + rfcomm bind)
cardiag --port socket://192.168.0.10:35000 info     # Wi-Fi adapters
```

Only CAN (ISO 15765-4) cars are supported. That covers US cars from model year
2008 and most European cars from about 2006.

## Commands

| Command | What it does |
| --- | --- |
| `info` | VIN, MIL, calibration IDs, responding ECUs and their PIDs |
| `dtc [read\|clear] [--kind pending\|permanent] [--all]` | OBD trouble codes |
| `freeze` | Freeze frame data for the code that turned on the MIL |
| `live [PID ...] [-i SEC] [-n N] [--csv FILE]` | Live data stream |
| `pids` | List the PIDs cardiag can decode |
| `uds scan [--start 700 --end 7EF]` | Find modules that answer UDS |
| `uds info --tx 7E0` | Part numbers, software versions, serial, VIN |
| `uds dtc --tx 760 [--clear]` | A module's trouble codes with status flags |
| `uds read --tx 7E0 F190 F187` | Read data identifiers |
| `uds raw --tx 7E0 22 F1 90` | Send raw bytes |
| `coding profiles` | List coding profiles and seed/key algorithms |
| `coding show PROFILE` | Read and decode a module's coding |
| `coding set PROFILE key=value ... [--dry-run] [--yes]` | Change coding |
| `coding backup PROFILE` / `coding restore PROFILE FILE` | Back up or restore coding |

Commands that change something (`dtc clear`, `uds dtc --clear`, `coding set`,
`coding restore`) ask for confirmation. If you're not at an interactive
terminal, they refuse unless you pass `--yes`.

## Coding profiles

Coding is model-specific, so cardiag describes each module with a JSON
profile. A profile gives the module's CAN IDs, the DID that holds the coding
block, the session and security level needed to write it, and the bit layout
of each option. See `cardiag/coding/profiles/demo_bcm.json` for a complete
example and `cardiag/coding/profile.py` for the format.

Put your own profiles in `~/.cardiag/profiles/`, or pass a path:
`cardiag coding show ./my_bcm.json`. Backups go to `~/.cardiag/backups/`.
Set `CARDIAG_HOME` to change the location.

**Security access.** Most modules need a seed/key exchange before they accept
writes. The algorithms are manufacturer-specific and are not included here.
Register your own in Python:

```python
from cardiag.coding import security

@security.register("my_brand_level1")
def my_key(seed: bytes, level: int) -> bytes:
    ...
```

Or reference one from a profile as `"algorithm": "my_package.keys:my_key"`.
That form imports and runs Python code, so only use profiles you trust.

> **Warning:** Wrong coding can disable features or modules, or make a car
> unroadworthy. Always try `--dry-run` first, keep the automatic backups, and
> use a stable power supply. You are responsible for changes you make to your
> vehicle.

## Architecture

```
cardiag/
  transport/   Transport interface, ELM327 driver, ISO-TP framing, simulator transport
  obd/         OBD-II client, PID decoders, DTC encoding and descriptions
  uds/         UDS client (sessions, DIDs, security access, DTCs, NRC names)
  coding/      Profiles, seed/key registry, read/backup/write/verify flow
  sim/         Virtual vehicle (4 ECUs) and an ELM327 serial emulator
  cli.py       Command line interface
```

The ELM327 driver runs the adapter with headers on and reassembles ISO-TP
itself, so it can tell apart replies from several ECUs to one broadcast.
Plain ELM327 chips can't send messages longer than 7 bytes, so for longer
requests (such as most coding writes) the driver switches off CAN
auto-formatting and sends the ISO-TP frames itself.

## Tests

```bash
pip install -e '.[dev]'
pytest
```

The client tests run twice: once against the simulator directly and once
through the ELM327 emulator, which tests the real adapter driver end to end.

## Possible next steps

- Support for other adapter types (J2534 pass-thru, SocketCAN, STN/OBDLink).
- Coding profiles for real modules.
- A GUI or web dashboard on top of the same library.
