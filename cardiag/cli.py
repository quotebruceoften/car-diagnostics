"""Command line interface: ``cardiag --help``."""
from __future__ import annotations

import argparse
import csv
import sys
import time
from datetime import datetime

from . import __version__
from .coding import Coder, available_profiles, find_profile
from .coding import security
from .errors import CarDiagError, NoResponseError
from .obd import OBDClient, ecu_name
from .obd import pids as pidmod
from .transport.base import Transport
from .uds import STANDARD_DIDS, NegativeResponseError, UDSClient, format_did_value


def _hex(text: str) -> int:
    return int(text, 16) if not text.lower().startswith("0x") else int(text, 0)


def _confirm(prompt: str, assume_yes: bool) -> bool:
    if assume_yes:
        return True
    if not sys.stdin.isatty():
        print(f"{prompt} - refusing without --yes (not an interactive terminal)", file=sys.stderr)
        return False
    return input(f"{prompt} [y/N] ").strip().lower() in ("y", "yes")


def open_transport(args) -> Transport:
    if args.sim or not args.port:
        if not args.sim:
            print("No --port given; using the built-in simulator (pass --port to use an adapter).\n",
                  file=sys.stderr)
        from .transport.simulator import SimulatorTransport

        return SimulatorTransport()
    from .transport.elm327 import ELM327Transport

    return ELM327Transport(args.port, baudrate=args.baud, protocol=args.protocol, timeout=args.timeout)


# --------------------------------------------------------------------- OBD
def cmd_info(t: Transport, args) -> int:
    obd = OBDClient(t)
    print(f"Interface : {t.description}")
    try:
        print(f"VIN       : {obd.vin()}")
    except NoResponseError:
        print("VIN       : (not reported)")
    status = obd.read("monitor_status")
    mil = "ON" if status.value["mil_on"] else "off"
    print(f"MIL       : {mil}  ({status.value['dtc_count']} stored DTCs)")
    for ecu, cal in obd.calibration_ids().items():
        print(f"Cal ID    : {cal}  [{ecu_name(ecu)}]")
    print("\nResponding ECUs and supported PIDs:")
    for ecu, supported in sorted(obd.supported_pids().items()):
        known = [pidmod.BY_NUMBER[p].name for p in sorted(supported) if p in pidmod.BY_NUMBER]
        print(f"  {ecu_name(ecu)} (0x{ecu:X}): {len(supported)} PIDs")
        print(f"    {', '.join(known)}")
    return 0


def cmd_dtc(t: Transport, args) -> int:
    obd = OBDClient(t)
    if args.action == "clear":
        if not _confirm("Clear all DTCs, freeze frames and readiness monitors?", args.yes):
            return 1
        acked = obd.clear_dtcs()
        print(f"Cleared by: {', '.join(ecu_name(e) for e in acked) or 'no ECU answered'}")
        return 0
    kinds = ["stored", "pending", "permanent"] if args.all else [args.kind]
    for kind in kinds:
        print(f"{kind.capitalize()} DTCs:")
        found = obd.read_dtcs(kind)
        codes = [(ecu, d) for ecu, ds in sorted(found.items()) for d in ds]
        if not codes:
            print("  none")
        for ecu, d in codes:
            print(f"  {d.code}  {d.description}  [{ecu_name(ecu)}]")
    return 0


def cmd_freeze(t: Transport, args) -> int:
    ff = OBDClient(t).freeze_frame()
    if not ff:
        print("No freeze frame stored.")
        return 0
    print(f"Freeze frame for {ff.pop('dtc')} [{ecu_name(ff.pop('ecu'))}]")
    for reading in ff.values():
        print(f"  {reading.pid.description:<40} {reading}")
    return 0


def cmd_live(t: Transport, args) -> int:
    obd = OBDClient(t)
    names = args.pids or ["rpm", "speed", "coolant_temp", "engine_load", "throttle", "module_voltage"]
    selected = [pidmod.lookup(n) for n in names]
    writer = None
    if args.csv:
        fh = open(args.csv, "w", newline="")
        writer = csv.writer(fh)
        writer.writerow(["timestamp"] + [f"{p.name} ({p.unit})" if p.unit else p.name for p in selected])
    tty = sys.stdout.isatty() and not args.no_clear
    count = 0
    try:
        while args.count is None or count < args.count:
            row = []
            lines = []
            for p in selected:
                try:
                    r = obd.read(p.pid)
                    row.append(r.value)
                    lines.append(f"  {p.description:<40} {r}")
                except NoResponseError:
                    row.append("")
                    lines.append(f"  {p.description:<40} (not supported)")
            stamp = datetime.now().isoformat(timespec="milliseconds")
            if tty:
                print("\033[2J\033[H", end="")
            print(f"Live data  {stamp}  (Ctrl+C to stop)")
            print("\n".join(lines))
            if not tty:
                print()
            if writer:
                writer.writerow([stamp] + row)
            count += 1
            if args.count is None or count < args.count:
                time.sleep(args.interval)
    except KeyboardInterrupt:
        pass
    finally:
        if writer:
            fh.close()
            print(f"Logged {count} samples to {args.csv}")
    return 0


def cmd_pids(t, args) -> int:
    for p in pidmod.all_pids():
        print(f"  0x{p.pid:02X}  {p.name:<22} {p.description}{f' [{p.unit}]' if p.unit else ''}")
    return 0


# --------------------------------------------------------------------- UDS
def _uds(t: Transport, args) -> UDSClient:
    return UDSClient(t, args.tx, args.rx)


def cmd_uds_scan(t: Transport, args) -> int:
    print(f"Scanning 0x{args.start:X}-0x{args.end:X} (response ID = request ID + 8)...")
    found = 0
    for tx in range(args.start, args.end + 1):
        uds = UDSClient(t, tx)
        try:
            uds.tester_present()
        except NegativeResponseError:
            pass  # it answered, so something is there
        except (NoResponseError, CarDiagError):
            continue
        found += 1
        name = part = ""
        try:
            name = format_did_value(uds.read_data_by_identifier(0xF197))
        except CarDiagError:
            pass
        try:
            part = format_did_value(uds.read_data_by_identifier(0xF187))
        except CarDiagError:
            pass
        print(f"  0x{tx:03X} -> 0x{tx + 8:03X}  {name:<16} {part}")
    print(f"{found} module(s) found.")
    return 0


def cmd_uds_info(t: Transport, args) -> int:
    info = _uds(t, args).identify()
    if not info:
        print("Module did not report any identification data.")
    for did, value in info.items():
        print(f"  {did:04X}  {STANDARD_DIDS[did]:<28} {format_did_value(value)}")
    return 0


def cmd_uds_read(t: Transport, args) -> int:
    uds = _uds(t, args)
    for did in args.dids:
        value = uds.read_data_by_identifier(did)
        print(f"  {did:04X}  {value.hex(' ').upper():<40} {format_did_value(value)}")
    return 0


def cmd_uds_dtc(t: Transport, args) -> int:
    uds = _uds(t, args)
    if args.clear:
        if not _confirm(f"Clear DTCs in module 0x{args.tx:X}?", args.yes):
            return 1
        uds.clear_dtcs()
        print("DTCs cleared.")
        return 0
    dtcs = uds.read_dtcs(args.mask)
    if not dtcs:
        print("No DTCs.")
    for d in dtcs:
        print(f"  {d.display:<10} {d.description}")
        print(f"             status 0x{d.status:02X}: {', '.join(d.status_flags())}")
    return 0


def cmd_uds_raw(t: Transport, args) -> int:
    payload = bytes.fromhex("".join(args.bytes))
    for m in t.send(args.tx, payload, args.rx or args.tx + 8):
        print(f"  0x{m.rx_id:X}: {m.data.hex(' ').upper()}")
    return 0


# ------------------------------------------------------------------ coding
def cmd_coding_profiles(t, args) -> int:
    profiles = available_profiles()
    if not profiles:
        print("No coding profiles found.")
    for p in profiles.values():
        print(f"  {p.id:<16} {p.name}  (module 0x{p.tx_id:X}, DID 0x{p.did:04X})")
        print(f"  {'':<16} {p.source}")
    print(f"\nSecurity algorithms: {', '.join(security.available())}")
    return 0


def _print_coding(profile, data: bytes) -> None:
    print(f"{profile.name}  -  coding {data.hex(' ').upper()}")
    for opt in profile.options:
        print(f"  {opt.key:<18} {opt.display(data):<14} {opt.label}  ({opt.describe_range()})")


def cmd_coding_show(t: Transport, args) -> int:
    profile = find_profile(args.profile)
    _print_coding(profile, Coder(t, profile).read())
    return 0


def cmd_coding_set(t: Transport, args) -> int:
    profile = find_profile(args.profile)
    coder = Coder(t, profile)
    changes = {}
    for item in args.changes:
        key, sep, value = item.partition("=")
        if not sep:
            raise CarDiagError(f"expected key=value, got {item!r}")
        changes[key.strip()] = value.strip()
    old = coder.read()
    new = profile.apply(old, changes)
    before, after = profile.decode(old), profile.decode(new)
    diff = [(k, before[k], after[k]) for k in after if before[k] != after[k]]
    if not diff:
        print("Nothing to change - module already has these settings.")
        return 0
    print(f"Module 0x{profile.tx_id:X}  {profile.name}")
    for key, a, b in diff:
        print(f"  {key:<18} {a}  ->  {b}")
    print(f"  coding {old.hex(' ').upper()}\n      -> {new.hex(' ').upper()}")
    if args.dry_run:
        print("Dry run: nothing written.")
        return 0
    if not _confirm("Write new coding to the module?", args.yes):
        return 1
    result = coder.write(new)
    print(f"Written and verified. Backup of previous coding: {result.backup}")
    return 0


def cmd_coding_backup(t: Transport, args) -> int:
    profile = find_profile(args.profile)
    print(f"Backup saved to {Coder(t, profile).backup()}")
    return 0


def cmd_coding_restore(t: Transport, args) -> int:
    profile = find_profile(args.profile)
    coder = Coder(t, profile)
    data = coder.load_backup(args.file)
    _print_coding(profile, data)
    if not _confirm("Restore this coding to the module?", args.yes):
        return 1
    result = coder.write(data)
    print(f"Restored and verified. Coding before restore was backed up to {result.backup}")
    return 0


# ------------------------------------------------------------------ parser
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="cardiag", description="Car diagnostics and ECU coding over OBD-II / UDS."
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    conn = parser.add_argument_group("connection")
    conn.add_argument("-p", "--port", help="adapter port: /dev/ttyUSB0, COM3, socket://192.168.0.10:35000")
    conn.add_argument("--sim", action="store_true", help="use the built-in simulated vehicle")
    conn.add_argument("--baud", type=int, default=38400, help="serial baud rate (default 38400)")
    conn.add_argument("--protocol", default="0", help="ELM327 protocol number, 0 = auto (default)")
    conn.add_argument("--timeout", type=float, default=5.0, help="adapter timeout in seconds")
    sub = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    p = sub.add_parser("info", help="vehicle overview: VIN, MIL, ECUs, supported PIDs")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("dtc", help="read or clear OBD trouble codes")
    p.add_argument("action", nargs="?", choices=["read", "clear"], default="read")
    p.add_argument("--kind", choices=["stored", "pending", "permanent"], default="stored")
    p.add_argument("--all", action="store_true", help="show stored, pending and permanent codes")
    p.add_argument("-y", "--yes", action="store_true", help="don't ask for confirmation")
    p.set_defaults(func=cmd_dtc)

    p = sub.add_parser("freeze", help="show the freeze frame stored with the first DTC")
    p.set_defaults(func=cmd_freeze)

    p = sub.add_parser("live", help="stream live sensor data")
    p.add_argument("pids", nargs="*", help="PID names or numbers (see 'cardiag pids')")
    p.add_argument("-i", "--interval", type=float, default=1.0, help="seconds between samples")
    p.add_argument("-n", "--count", type=int, help="stop after N samples")
    p.add_argument("--csv", help="also log samples to this CSV file")
    p.add_argument("--no-clear", action="store_true", help="don't redraw the screen")
    p.set_defaults(func=cmd_live)

    p = sub.add_parser("pids", help="list the PIDs cardiag can decode")
    p.set_defaults(func=cmd_pids, offline=True)

    uds = sub.add_parser("uds", help="UDS (ISO 14229) module-level diagnostics").add_subparsers(
        dest="uds_command", required=True, metavar="ACTION"
    )

    def module_args(sp):
        sp.add_argument("--tx", type=_hex, required=True, help="module request ID, e.g. 7E0")
        sp.add_argument("--rx", type=_hex, help="module response ID (default: tx + 8)")

    p = uds.add_parser("scan", help="find modules that answer UDS")
    p.add_argument("--start", type=_hex, default=0x700)
    p.add_argument("--end", type=_hex, default=0x7EF)
    p.set_defaults(func=cmd_uds_scan)

    p = uds.add_parser("info", help="read a module's identification DIDs")
    module_args(p)
    p.set_defaults(func=cmd_uds_info)

    p = uds.add_parser("read", help="read data identifiers")
    module_args(p)
    p.add_argument("dids", nargs="+", type=_hex, help="DIDs in hex, e.g. F190")
    p.set_defaults(func=cmd_uds_read)

    p = uds.add_parser("dtc", help="read (or --clear) a module's DTCs")
    module_args(p)
    p.add_argument("--mask", type=_hex, default=0xFF, help="DTC status mask (default FF)")
    p.add_argument("--clear", action="store_true")
    p.add_argument("-y", "--yes", action="store_true")
    p.set_defaults(func=cmd_uds_dtc)

    p = uds.add_parser("raw", help="send raw bytes and print the reply")
    module_args(p)
    p.add_argument("bytes", nargs="+", help="hex bytes, e.g. 22 F1 90")
    p.set_defaults(func=cmd_uds_raw)

    coding = sub.add_parser("coding", help="read and change module coding").add_subparsers(
        dest="coding_command", required=True, metavar="ACTION"
    )
    p = coding.add_parser("profiles", help="list available coding profiles")
    p.set_defaults(func=cmd_coding_profiles, offline=True)

    p = coding.add_parser("show", help="read and decode a module's coding")
    p.add_argument("profile", help="profile id or path to a profile .json")
    p.set_defaults(func=cmd_coding_show)

    p = coding.add_parser("set", help="change coding options (backs up first)")
    p.add_argument("profile")
    p.add_argument("changes", nargs="+", metavar="key=value")
    p.add_argument("--dry-run", action="store_true", help="show the change without writing")
    p.add_argument("-y", "--yes", action="store_true", help="don't ask for confirmation")
    p.set_defaults(func=cmd_coding_set)

    p = coding.add_parser("backup", help="save the current coding to a file")
    p.add_argument("profile")
    p.set_defaults(func=cmd_coding_backup)

    p = coding.add_parser("restore", help="write a previously saved backup")
    p.add_argument("profile")
    p.add_argument("file")
    p.add_argument("-y", "--yes", action="store_true")
    p.set_defaults(func=cmd_coding_restore)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if getattr(args, "offline", False):
            return args.func(None, args)
        with open_transport(args) as transport:
            return args.func(transport, args)
    except CarDiagError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
