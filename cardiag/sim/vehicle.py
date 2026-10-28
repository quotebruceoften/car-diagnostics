"""A virtual vehicle with OBD-II and UDS capable ECUs, for demos and tests."""
from __future__ import annotations

import math
import os
import time

from ..coding.security import demo_xor
from ..obd.dtc import encode as encode_dtc

OBD_BROADCAST_ID = 0x7DF


class VirtualECU:
    def __init__(
        self,
        name: str,
        tx_id: int,
        rx_id: int,
        dids: dict[int, bytes] | None = None,
        protected_dids: set[int] | None = None,
        uds_dtcs: list[tuple[str, int, int]] | None = None,
    ) -> None:
        self.name = name
        self.tx_id = tx_id  # the ID this ECU listens on
        self.rx_id = rx_id  # the ID it answers with
        self.dids = dict(dids or {})
        self.protected_dids = set(protected_dids or ())  # writable after security access
        self.uds_dtcs = list(uds_dtcs or [])  # (code, failure type, status)
        self.session = 0x01
        self.unlocked = False
        self._seed: bytes | None = None
        self._failed_keys = 0

    obd = False

    def handle_obd(self, payload: bytes) -> bytes | None:
        return None

    def handle(self, payload: bytes) -> bytes | None:
        sid = payload[0]
        if sid < 0x10:
            return self.handle_obd(payload)
        handler = getattr(self, f"_uds_{sid:02x}", None)
        if handler is None:
            return bytes([0x7F, sid, 0x11])
        return handler(payload)

    @staticmethod
    def _nrc(sid: int, code: int) -> bytes:
        return bytes([0x7F, sid, code])

    # --------------------------------------------------------------- UDS
    def _uds_10(self, p: bytes) -> bytes:
        if len(p) != 2:
            return self._nrc(0x10, 0x13)
        if p[1] not in (0x01, 0x02, 0x03):
            return self._nrc(0x10, 0x12)
        if p[1] != self.session:
            self.unlocked = False
        self.session = p[1]
        return bytes([0x50, p[1], 0x00, 0x32, 0x01, 0xF4])

    def _uds_11(self, p: bytes) -> bytes:
        self.session, self.unlocked = 0x01, False
        return bytes([0x51, p[1] if len(p) > 1 else 0x01])

    def _uds_3e(self, p: bytes) -> bytes | None:
        if len(p) > 1 and p[1] & 0x80:
            return None
        return b"\x7E\x00"

    def _uds_22(self, p: bytes) -> bytes:
        if len(p) != 3:
            return self._nrc(0x22, 0x13)
        did = (p[1] << 8) | p[2]
        if did == 0xF186:
            return bytes([0x62, p[1], p[2], self.session])
        if did not in self.dids:
            return self._nrc(0x22, 0x31)
        return bytes([0x62, p[1], p[2]]) + self.dids[did]

    def _uds_2e(self, p: bytes) -> bytes:
        if len(p) < 4:
            return self._nrc(0x2E, 0x13)
        did = (p[1] << 8) | p[2]
        if did not in self.protected_dids:
            return self._nrc(0x2E, 0x31)
        if self.session != 0x03:
            return self._nrc(0x2E, 0x7F)
        if not self.unlocked:
            return self._nrc(0x2E, 0x33)
        if len(p) - 3 != len(self.dids[did]):
            return self._nrc(0x2E, 0x13)
        self.dids[did] = bytes(p[3:])
        return bytes([0x6E, p[1], p[2]])

    def _uds_27(self, p: bytes) -> bytes:
        if len(p) < 2:
            return self._nrc(0x27, 0x13)
        if self.session == 0x01:
            return self._nrc(0x27, 0x7F)
        level = p[1]
        if level % 2 == 1:
            if self._failed_keys >= 3:
                return self._nrc(0x27, 0x36)
            if self.unlocked:
                return bytes([0x67, level, 0, 0, 0, 0])
            self._seed = os.urandom(4)
            return bytes([0x67, level]) + self._seed
        if self._seed is None:
            return self._nrc(0x27, 0x24)
        expected = demo_xor(self._seed, level - 1)
        self._seed = None
        if bytes(p[2:]) != expected:
            self._failed_keys += 1
            return self._nrc(0x27, 0x35)
        self.unlocked = True
        self._failed_keys = 0
        return bytes([0x67, level])

    def _uds_19(self, p: bytes) -> bytes:
        if len(p) < 3 or p[1] != 0x02:
            return self._nrc(0x19, 0x12)
        out = bytearray([0x59, 0x02, 0xFF])
        for code, ftb, status in self.uds_dtcs:
            if status & p[2]:
                out += encode_dtc(code) + bytes([ftb, status])
        return bytes(out)

    def _uds_14(self, p: bytes) -> bytes:
        if len(p) != 4:
            return self._nrc(0x14, 0x13)
        self.uds_dtcs.clear()
        self.clear_obd()
        return b"\x54"

    def clear_obd(self) -> None:
        pass


class OBDECU(VirtualECU):
    """An emissions-relevant ECU that also answers SAE J1979 requests."""

    obd = True

    def __init__(self, *args, vin: str = "", stored=(), pending=(), permanent=(), live=None, **kw) -> None:
        super().__init__(*args, **kw)
        self.vin = vin
        self.stored = list(stored)
        self.pending = list(pending)
        self.permanent = list(permanent)
        self.live = live or {}  # pid -> callable(t) -> bytes
        self.freeze: dict[int, bytes] = {}
        self.distance_since_clear = 1234
        self._t0 = time.monotonic()
        if self.stored:
            self.capture_freeze_frame()

    def capture_freeze_frame(self) -> None:
        t = 12.5
        self.freeze = {pid: fn(t) for pid, fn in self.live.items()}
        self.freeze[0x02] = encode_dtc(self.stored[0])

    def clear_obd(self) -> None:
        self.stored.clear()
        self.pending.clear()
        self.freeze = {}
        self.distance_since_clear = 0

    def _supported(self) -> set[int]:
        return set(self.live) | {0x01, 0x31}

    def _pid_bytes(self, pid: int) -> bytes | None:
        if pid % 0x20 == 0:
            # "PIDs supported" bitmap; the last bit says the next range exists.
            supported = self._supported()
            if pid and not any(p > pid for p in supported):
                return None
            bits = 0
            for i in range(32):
                n = pid + i + 1
                if n in supported or (i == 31 and any(p > n for p in supported)):
                    bits |= 1 << (31 - i)
            return bits.to_bytes(4, "big")
        if pid == 0x01:
            count = len(self.stored)
            mil = 0x80 if self.stored else 0
            return bytes([mil | count, 0x07, 0x65, 0x00])
        if pid == 0x31:
            return self.distance_since_clear.to_bytes(2, "big")
        if pid in self.live:
            return self.live[pid](time.monotonic() - self._t0)
        return None

    def handle_obd(self, p: bytes) -> bytes | None:
        mode = p[0]
        if mode == 0x01 and len(p) >= 2:
            # Up to 6 PIDs may be requested at once.
            out = bytearray([0x41])
            for pid in p[1:7]:
                data = self._pid_bytes(pid)
                if data is not None:
                    out += bytes([pid]) + data
            return bytes(out) if len(out) > 1 else None
        if mode == 0x02 and len(p) >= 3:
            pid, frame = p[1], p[2]
            if pid == 0x00:
                bits = 0
                for n in self.freeze:
                    if 1 <= n <= 32:
                        bits |= 1 << (32 - n)
                return bytes([0x42, 0x00, frame]) + bits.to_bytes(4, "big")
            if pid == 0x02:
                return bytes([0x42, 0x02, frame]) + self.freeze.get(0x02, b"\x00\x00")
            if pid in self.freeze:
                return bytes([0x42, pid, frame]) + self.freeze[pid]
            return None
        if mode in (0x03, 0x07, 0x0A):
            codes = {0x03: self.stored, 0x07: self.pending, 0x0A: self.permanent}[mode]
            return bytes([mode + 0x40, len(codes)]) + b"".join(encode_dtc(c) for c in codes)
        if mode == 0x04:
            self.clear_obd()
            return b"\x44"
        if mode == 0x09 and len(p) >= 2:
            if p[1] == 0x00:
                return bytes([0x49, 0x00, 0x54, 0x00, 0x00, 0x00])  # 02, 04 supported
            if p[1] == 0x02 and self.vin:
                return bytes([0x49, 0x02, 0x01]) + self.vin.encode("ascii")
            if p[1] == 0x04:
                cal = self.dids.get(0xF188, b"CAL0000000000000")[:16].ljust(16, b"\x00")
                return bytes([0x49, 0x04, 0x01]) + cal
        return None


def _engine_live() -> dict:
    def rpm(t):
        v = 800 + 1800 * (1 + math.sin(t / 3)) / 2
        return int(v * 4).to_bytes(2, "big")

    def speed(t):
        return bytes([int(60 * (1 + math.sin(t / 3 - 0.6)) / 2)])

    def coolant(t):
        return bytes([40 + min(90, int(20 + t * 2))])

    def load(t):
        return bytes([int(255 * (0.2 + 0.4 * (1 + math.sin(t / 3)) / 2))])

    def throttle(t):
        return bytes([int(255 * (0.12 + 0.5 * (1 + math.sin(t / 3)) / 2))])

    def maf(t):
        return int(100 * (3 + 20 * (1 + math.sin(t / 3)) / 2)).to_bytes(2, "big")

    return {
        0x04: load,
        0x05: coolant,
        0x06: lambda t: bytes([128 + int(6 * math.sin(t))]),
        0x07: lambda t: bytes([131]),
        0x0B: lambda t: bytes([int(30 + 60 * (1 + math.sin(t / 3)) / 2)]),
        0x0C: rpm,
        0x0D: speed,
        0x0E: lambda t: bytes([int((12 + 8 * math.sin(t / 3) + 64) * 2)]),
        0x0F: lambda t: bytes([40 + 24]),
        0x10: maf,
        0x11: throttle,
        0x1F: lambda t: int(t).to_bytes(2, "big"),
        0x2F: lambda t: bytes([int(255 * 0.62)]),
        0x33: lambda t: bytes([101]),
        0x42: lambda t: int(14100 + 150 * math.sin(t)).to_bytes(2, "big"),
        0x46: lambda t: bytes([40 + 18]),
        0x5C: lambda t: bytes([40 + min(100, int(15 + t * 1.5))]),
    }


class Vehicle:
    def __init__(self, name: str, vin: str, ecus: list[VirtualECU]) -> None:
        self.name = name
        self.vin = vin
        self.ecus = ecus

    def ecu(self, tx_id: int) -> VirtualECU | None:
        return next((e for e in self.ecus if e.tx_id == tx_id), None)

    def handle(self, tx_id: int, payload: bytes) -> list[tuple[int, bytes]]:
        """Deliver a request; return [(response CAN id, payload)]."""
        if not payload:
            return []
        if tx_id == OBD_BROADCAST_ID:
            targets = [e for e in self.ecus if e.obd]
        else:
            ecu = self.ecu(tx_id)
            targets = [ecu] if ecu else []
        replies = []
        for ecu in targets:
            reply = ecu.handle(payload)
            if reply is not None:
                replies.append((ecu.rx_id, reply))
        return replies

    @classmethod
    def demo(cls) -> "Vehicle":
        vin = "WVWZZZ1KZ8W123456"
        engine = OBDECU(
            "Engine control module",
            0x7E0,
            0x7E8,
            vin=vin,
            stored=["P0301", "P0420"],
            pending=["P0171"],
            permanent=["P0420"],
            live=_engine_live(),
            dids={
                0xF187: b"06K907425B",
                0xF188: b"SC800H6300000000",
                0xF189: b"0410",
                0xF18C: b"EM1234567890",
                0xF190: vin.encode(),
                0xF197: b"ENGINE ECM",
            },
            uds_dtcs=[("P0301", 0x00, 0x2B), ("P0420", 0x00, 0x2B), ("P0171", 0x00, 0x24)],
        )
        transmission = OBDECU(
            "Transmission control module",
            0x7E1,
            0x7E9,
            pending=["P0730"],
            live={0x0D: _engine_live()[0x0D], 0x46: lambda t: bytes([58])},
            dids={0xF187: b"09G927750LB", 0xF189: b"1012", 0xF190: vin.encode(), 0xF197: b"TCM AQ250"},
            uds_dtcs=[("P0730", 0x00, 0x24)],
        )
        abs_module = VirtualECU(
            "ABS / ESC",
            0x760,
            0x768,
            dids={0xF187: b"1K0907379BE", 0xF189: b"0101", 0xF190: vin.encode(), 0xF197: b"ESP MK60EC1"},
            uds_dtcs=[("C0035", 0x1F, 0x28)],
        )
        bcm = VirtualECU(
            "Body control module",
            0x726,
            0x72E,
            dids={
                0xF187: b"5K0937087AC",
                0xF189: b"0254",
                0xF190: vin.encode(),
                0xF197: b"BCM PQ35",
                # drl on, auto-lock 15 km/h, seatbelt chime on; 3 blinks; 30 s; EU
                0x0600: bytes([0x15, 0x03, 0x1E, 0x00, 0x00, 0x00, 0x00, 0x00]),
            },
            protected_dids={0x0600},
            uds_dtcs=[("U0155", 0x00, 0x08)],
        )
        return cls("Demo hatchback", vin, [engine, transmission, abs_module, bcm])
