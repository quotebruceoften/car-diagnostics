"""OBD-II (SAE J1979 / ISO 15031-5) client."""
from __future__ import annotations

from dataclasses import dataclass

from ..errors import NoResponseError, ProtocolError
from ..transport.base import OBD_BROADCAST_ID, Transport
from . import dtc as dtcmod
from . import pids as pidmod

ECU_NAMES = {
    0x7E8: "Engine (ECM)",
    0x7E9: "Transmission (TCM)",
    0x7EA: "ECU #3",
    0x7EB: "ECU #4",
    0x7EC: "Hybrid/EV",
    0x7ED: "ECU #6",
    0x7EE: "ECU #7",
    0x7EF: "ECU #8",
}


def ecu_name(rx_id: int) -> str:
    return ECU_NAMES.get(rx_id, f"ECU 0x{rx_id:X}")


@dataclass(frozen=True)
class Reading:
    pid: pidmod.PID
    value: object
    ecu: int

    def __str__(self) -> str:
        unit = f" {self.pid.unit}" if self.pid.unit else ""
        return f"{self.value}{unit}"


class OBDClient:
    def __init__(self, transport: Transport, tx_id: int = OBD_BROADCAST_ID) -> None:
        self.transport = transport
        self.tx_id = tx_id

    # ----------------------------------------------------------------- basics
    def query(self, mode: int, *params: int) -> dict[int, bytes]:
        """Send an OBD request; return {ecu rx id: data after the echoed mode/params}."""
        request = bytes([mode, *params])
        positive = mode + 0x40
        results: dict[int, bytes] = {}
        for msg in self.transport.send(self.tx_id, request):
            if not msg.data:
                continue
            if msg.data[0] == 0x7F:
                continue  # negative response: this ECU doesn't support it
            if msg.data[0] != positive:
                raise ProtocolError(f"unexpected reply {msg.data.hex()} to {request.hex()}")
            echo_len = 1 + len(params)
            if mode in (0x03, 0x07, 0x0A, 0x04):
                echo_len = 1
            results[msg.rx_id] = msg.data[echo_len:]
        return results

    def _first(self, results: dict[int, bytes], what: str) -> tuple[int, bytes]:
        if not results:
            raise NoResponseError(f"no ECU answered {what}")
        ecu = min(results)
        return ecu, results[ecu]

    # ------------------------------------------------------------------- PIDs
    def supported_pids(self) -> dict[int, set[int]]:
        """Return {ecu: set of supported mode 01 PIDs}."""
        supported: dict[int, set[int]] = {}
        base = 0x00
        pending = None
        while base <= 0xE0:
            results = self.query(0x01, base)
            if pending is not None:
                results = {k: v for k, v in results.items() if k in pending}
            if not results:
                break
            for ecu, data in results.items():
                supported.setdefault(ecu, set()).update(pidmod.decode_supported(base, data))
            # Continue only with ECUs that advertise the next range.
            pending = {ecu for ecu, s in supported.items() if base + 0x20 in s}
            if not pending:
                break
            base += 0x20
        for s in supported.values():
            s.difference_update({0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0})
        return supported

    def read(self, pid: str | int) -> Reading:
        """Read one PID from the first (lowest-ID) ECU that answers."""
        p = pidmod.lookup(pid)
        ecu, data = self._first(self.query(0x01, p.pid), p.name)
        if len(data) < p.length:
            raise ProtocolError(f"short reply for {p.name}: {data.hex()}")
        return Reading(p, p.decode(data[: p.length]), ecu)

    def freeze_frame(self, frame: int = 0) -> dict[str, object]:
        """Read the stored freeze frame: the DTC that triggered it plus key PIDs."""
        ecu, data = self._first(self.query(0x02, 0x02, frame), "freeze frame DTC")
        if data[:2] == b"\x00\x00":
            return {}
        result: dict[str, object] = {"dtc": dtcmod.decode(data[:2]), "ecu": ecu}
        for p in pidmod.all_pids():
            if p.pid in (0x01,):
                continue
            reply = self.query(0x02, p.pid, frame).get(ecu)
            if reply and len(reply) >= p.length:
                result[p.name] = Reading(p, p.decode(reply[: p.length]), ecu)
        return result

    # ------------------------------------------------------------------- DTCs
    def read_dtcs(self, kind: str = "stored") -> dict[int, list[dtcmod.DTC]]:
        """kind: 'stored' (mode 03), 'pending' (mode 07) or 'permanent' (mode 0A)."""
        mode = {"stored": 0x03, "pending": 0x07, "permanent": 0x0A}[kind]
        return {ecu: dtcmod.parse_obd_response(data) for ecu, data in self.query(mode).items()}

    def clear_dtcs(self) -> list[int]:
        """Mode 04: clear DTCs and freeze frames, reset monitors. Returns ECUs that acked."""
        return sorted(self.query(0x04))

    # ---------------------------------------------------------- vehicle info
    def vin(self) -> str:
        _, data = self._first(self.query(0x09, 0x02), "VIN request")
        # CAN replies carry a 1-byte "number of data items" before the VIN.
        raw = data[1:] if len(data) == 18 else data
        return raw.decode("ascii", errors="replace").strip("\x00 ")

    def calibration_ids(self) -> dict[int, str]:
        out = {}
        for ecu, data in self.query(0x09, 0x04).items():
            text = data[1:].replace(b"\x00", b" ").decode("ascii", errors="replace")
            out[ecu] = " ".join(text.split())
        return out
