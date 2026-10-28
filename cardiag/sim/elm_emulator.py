"""A serial-port stand-in that behaves like an ELM327 attached to a virtual vehicle.

It lets the real :class:`~cardiag.transport.elm327.ELM327Transport` be
exercised end to end (AT commands, CAN frame formatting, ISO-TP) without
hardware. It implements the subset of the ELM327 command set the driver uses.
"""
from __future__ import annotations

from ..transport import isotp
from .vehicle import OBD_BROADCAST_ID, Vehicle


class ELM327Emulator:
    name = "elm327-emulator"

    def __init__(self, vehicle: Vehicle | None = None, protocol: int = 6) -> None:
        self.vehicle = vehicle or Vehicle.demo()
        self.protocol = protocol  # 6 = ISO 15765-4 CAN 11-bit 500 kbaud
        self.log: list[str] = []  # every command received, for tests
        self._out = bytearray()
        self._in = bytearray()
        self._reset()

    def _reset(self) -> None:
        self.echo = True
        self.headers = False
        self.spaces = True
        self.caf = True
        self.header = OBD_BROADCAST_ID
        self.rx_filter: int | None = None
        self.connected = False
        self._tx_partial: tuple[int, bytearray, int] | None = None

    # ------------------------------------------------------ serial interface
    @property
    def in_waiting(self) -> int:
        return len(self._out)

    def read(self, size: int = 1) -> bytes:
        data = bytes(self._out[:size])
        del self._out[:size]
        return data

    def reset_input_buffer(self) -> None:
        self._out.clear()

    def write(self, data: bytes) -> int:
        self._in.extend(data)
        while b"\r" in self._in:
            line, _, rest = bytes(self._in).partition(b"\r")
            self._in = bytearray(rest)
            self._process(line.decode("ascii").strip())
        return len(data)

    def close(self) -> None:
        pass

    # ------------------------------------------------------------ commands
    def _reply(self, cmd: str, lines: list[str]) -> None:
        text = (cmd + "\r" if self.echo else "") + "".join(l + "\r" for l in lines) + "\r>"
        self._out.extend(text.encode("ascii"))

    def _process(self, cmd: str) -> None:
        self.log.append(cmd)
        c = cmd.upper().replace(" ", "")
        if c.startswith("AT"):
            self._reply(cmd, self._at(c[2:]))
        elif c and all(ch in "0123456789ABCDEF" for ch in c) and len(c) % 2 == 0:
            self._reply(cmd, self._data(bytes.fromhex(c)))
        else:
            self._reply(cmd, ["?"])

    def _at(self, c: str) -> list[str]:
        if c in ("Z", "WS"):
            self._reset()
            return ["", "ELM327 v1.5"]
        if c == "I":
            return ["ELM327 v1.5"]
        flags = {"E0": ("echo", False), "E1": ("echo", True), "H0": ("headers", False),
                 "H1": ("headers", True), "S0": ("spaces", False), "S1": ("spaces", True),
                 "CAF0": ("caf", False), "CAF1": ("caf", True)}
        if c in flags:
            setattr(self, *flags[c])
            return ["OK"]
        if c in ("L0", "L1", "AT0", "AT1", "AT2") or c.startswith("ST") or c.startswith("SP"):
            return ["OK"]
        if c == "DPN":
            return [f"A{self.protocol:X}" if self.connected else "0"]
        if c == "DP":
            return ["ISO 15765-4 (CAN 11/500)"]
        if c == "RV":
            return ["14.1V"]
        if c.startswith("SH"):
            self.header = int(c[2:], 16)
            return ["OK"]
        if c.startswith("CRA"):
            self.rx_filter = int(c[3:], 16)
            return ["OK"]
        if c == "AR":
            self.rx_filter = None
            return ["OK"]
        return ["?"]

    def _fmt(self, can_id: int, frame: bytes) -> str:
        body = (frame.hex(" ") if self.spaces else frame.hex()).upper()
        if not self.headers:
            return body
        sep = " " if self.spaces else ""
        return f"{can_id:03X}{sep}{body}"

    def _data(self, data: bytes) -> list[str]:
        searching = [] if self.connected else ["SEARCHING..."]
        self.connected = True
        if self.caf:
            if len(data) > 7:
                return searching + ["?"]
            framed = [(rx, f) for rx, p in self.vehicle.handle(self.header, data) for f in isotp.segment(p)]
        else:
            framed = self._raw_frame(data)
            if isinstance(framed, str):
                return searching + [framed]
        lines = [
            self._fmt(rx_id, frame)
            for rx_id, frame in framed
            if self.rx_filter is None or rx_id == self.rx_filter
        ]
        return searching + (lines or ["NO DATA"])

    def _raw_frame(self, frame: bytes):
        """CAN auto formatting off: we were given a raw ISO-TP frame."""
        kind = frame[0] >> 4
        ecu = self.vehicle.ecu(self.header)
        if kind == 0x0:
            return self._first_frames(self.vehicle.handle(self.header, frame[1 : 1 + (frame[0] & 0x0F)]))
        if kind == 0x1:
            length = ((frame[0] & 0x0F) << 8) | frame[1]
            self._tx_partial = (length, bytearray(frame[2:]), 1)
            if ecu is None:
                return "NO DATA"
            return [(ecu.rx_id, b"\x30\x00\x00\x00\x00\x00\x00\x00")]  # flow control: send all
        if kind == 0x2 and self._tx_partial:
            length, buf, seq = self._tx_partial
            if frame[0] & 0x0F != seq & 0x0F:
                self._tx_partial = None
                return "NO DATA"
            buf.extend(frame[1:])
            if len(buf) < length:
                self._tx_partial = (length, buf, seq + 1)
                return "NO DATA"
            self._tx_partial = None
            return self._first_frames(self.vehicle.handle(self.header, bytes(buf[:length])))
        return "NO DATA"

    @staticmethod
    def _first_frames(replies):
        # With CAF off the adapter sends no flow control, so only the first
        # frame of a multi-frame reply would ever arrive.
        return [(rx, isotp.segment(p)[0]) for rx, p in replies]
