"""Driver for ELM327-compatible OBD adapters (USB, Bluetooth serial, Wi-Fi).

Only CAN protocols (ISO 15765-4, ATSP 6-9) are supported. That covers
virtually every car sold in the US since 2008 and in the EU since ~2006.

The adapter is run with headers on and spaces off, and responses are
reassembled here (rather than relying on the adapter's formatting) so that
replies from several ECUs to one broadcast request can be told apart.
"""
from __future__ import annotations

import string
import time

from ..errors import NoResponseError, ProtocolError, TransportError
from . import isotp
from .base import Message, Transport

_HEX = set(string.hexdigits)

_FATAL_REPLIES = (
    "UNABLE TO CONNECT",
    "CAN ERROR",
    "BUS ERROR",
    "BUS INIT",
    "FB ERROR",
    "DATA ERROR",
    "<DATA ERROR",
    "<RX ERROR",
    "BUFFER FULL",
    "LV RESET",
    "ACT ALERT",
    "STOPPED",
    "ERR",
)

# ELM327 "AT DPN" protocol numbers -> CAN identifier length in hex digits.
_CAN_PROTOCOLS = {6: 3, 7: 8, 8: 3, 9: 8}


class ELM327Transport(Transport):
    """Diagnostic transport over an ELM327 adapter.

    ``port`` is a serial device (``/dev/ttyUSB0``, ``COM3``), a pyserial URL
    such as ``socket://192.168.0.10:35000`` for Wi-Fi adapters, or an already
    open file-like port object (used by tests with the emulator).
    """

    def __init__(
        self,
        port,
        baudrate: int = 38400,
        protocol: str = "0",
        timeout: float = 5.0,
        response_timeout_ms: int = 500,
        initialize: bool = True,
    ) -> None:
        if isinstance(port, str):
            try:
                import serial
            except ImportError as exc:  # pragma: no cover
                raise TransportError("pyserial is required: pip install pyserial") from exc
            try:
                self._port = serial.serial_for_url(port, baudrate=baudrate, timeout=0.05)
            except (serial.SerialException, OSError) as exc:
                raise TransportError(f"cannot open {port}: {exc}") from exc
            self._port_name = port
        else:
            self._port = port
            self._port_name = getattr(port, "name", "custom port")
        self.timeout = timeout
        self.protocol = protocol
        self._st = max(1, min(0xFF, response_timeout_ms // 4))
        self.version = ""
        self.protocol_number: int | None = None
        self._id_len = 3
        self._tx_id: int | None = None
        self._rx_id: int | None = -1  # sentinel: filter state unknown
        if initialize:
            self.initialize()

    # ------------------------------------------------------------------ setup
    def initialize(self) -> None:
        lines = self._command("ATZ", timeout=max(self.timeout, 3.0))
        self.version = next((l for l in lines if "ELM" in l.upper()), lines[-1] if lines else "")
        for cmd in ("ATE0", "ATL0", "ATS0", "ATH1", "ATCAF1", f"ATST{self._st:02X}", f"ATSP{self.protocol}"):
            self._expect_ok(cmd)
        # Any OBD request makes the adapter search for / lock onto the protocol.
        lines = self._command("0100", timeout=max(self.timeout, 10.0))
        for line in lines:
            if line.startswith("UNABLE TO CONNECT"):
                raise NoResponseError("adapter could not connect to the vehicle (ignition on?)")
        dpn = self._command("ATDPN")[-1].upper().lstrip("A")
        try:
            self.protocol_number = int(dpn, 16)
        except ValueError as exc:
            raise TransportError(f"unexpected AT DPN reply: {dpn!r}") from exc
        if self.protocol_number not in _CAN_PROTOCOLS:
            raise TransportError(
                f"vehicle uses OBD protocol {self.protocol_number}; only CAN (6-9) is supported"
            )
        self._id_len = _CAN_PROTOCOLS[self.protocol_number]
        self._tx_id = None
        self._rx_id = -1

    @property
    def description(self) -> str:
        return f"{self.version or 'ELM327'} on {self._port_name} (protocol {self.protocol_number})"

    def close(self) -> None:
        close = getattr(self._port, "close", None)
        if close:
            close()

    # -------------------------------------------------------------- low level
    def _command(self, cmd: str, timeout: float | None = None) -> list[str]:
        reset = getattr(self._port, "reset_input_buffer", None)
        if reset:
            reset()
        self._port.write((cmd + "\r").encode("ascii"))
        deadline = time.monotonic() + (timeout or self.timeout)
        buf = bytearray()
        while not buf.endswith(b">"):
            if time.monotonic() > deadline:
                raise TransportError(f"timeout waiting for adapter reply to {cmd!r}")
            waiting = getattr(self._port, "in_waiting", 0) or 1
            buf.extend(self._port.read(waiting))
        text = buf[:-1].decode("ascii", errors="replace").replace("\r", "\n")
        lines = [l.strip() for l in text.split("\n")]
        return [l for l in lines if l and l.replace(" ", "") != cmd.replace(" ", "")]

    def _expect_ok(self, cmd: str) -> None:
        lines = self._command(cmd)
        if not lines or lines[-1].upper() != "OK":
            raise TransportError(f"adapter rejected {cmd!r}: {lines}")

    def _set_ids(self, tx_id: int, rx_id: int | None) -> None:
        if tx_id != self._tx_id:
            if self._id_len == 3:
                self._expect_ok(f"ATSH{tx_id:03X}")
            else:
                self._expect_ok(f"ATCP{(tx_id >> 24) & 0x1F:02X}")
                self._expect_ok(f"ATSH{tx_id & 0xFFFFFF:06X}")
            self._tx_id = tx_id
        if rx_id != self._rx_id:
            if rx_id is None:
                self._expect_ok("ATAR")
            else:
                self._expect_ok(f"ATCRA{rx_id:0{self._id_len}X}")
            self._rx_id = rx_id

    def _parse_into(self, lines: list[str], reasm: isotp.Reassembler) -> None:
        for line in lines:
            upper = line.upper()
            if upper in ("NO DATA", "OK") or upper.startswith("SEARCHING"):
                continue
            if upper == "?":
                raise TransportError("adapter did not understand the request")
            if any(upper.startswith(err) for err in _FATAL_REPLIES):
                raise TransportError(f"adapter reported: {line}")
            compact = upper.replace(" ", "")
            if not set(compact) <= _HEX or len(compact) <= self._id_len:
                raise ProtocolError(f"unexpected adapter output: {line!r}")
            can_id = int(compact[: self._id_len], 16)
            body = compact[self._id_len :]
            if len(body) % 2:
                raise ProtocolError(f"odd-length frame: {line!r}")
            reasm.feed(can_id, bytes.fromhex(body))

    # -------------------------------------------------------------- transport
    def send(self, tx_id: int, payload: bytes, rx_id: int | None = None) -> list[Message]:
        if not payload:
            raise ValueError("empty payload")
        self._set_ids(tx_id, rx_id)
        reasm = isotp.Reassembler()
        if len(payload) <= 7:
            self._parse_into(self._command(payload.hex().upper()), reasm)
        else:
            if rx_id is None:
                raise ValueError("multi-frame requests need a physical rx_id")
            self._send_multiframe(payload, rx_id, reasm)
        return [Message(can_id, data) for can_id, data in reasm.messages]

    def _send_multiframe(self, payload: bytes, rx_id: int, reasm: isotp.Reassembler) -> None:
        """Send a >7 byte request by driving ISO-TP manually with CAN auto-formatting off.

        Plain ELM327 chips cannot segment outgoing messages, so we send the
        first frame, wait for the ECU's flow control, then send consecutive
        frames ourselves.  The ECU's reply must fit in a single frame, which is
        true for the services we use this for (WriteDataByIdentifier etc.).
        """
        frames = isotp.segment(payload)
        self._expect_ok("ATCAF0")
        try:
            fc = self._read_flow_control(self._command(frames[0].hex().upper()), rx_id, reasm)
            if fc is None:
                return
            block_size, st_min = fc
            sent_in_block = 0
            for i, frame in enumerate(frames[1:], start=1):
                last = i == len(frames) - 1
                block_end = block_size and sent_in_block + 1 == block_size and not last
                if last or block_end:
                    lines = self._command(frame.hex().upper())
                else:
                    # No reply is expected: keep the adapter's wait short.
                    self._expect_ok("ATST02")
                    try:
                        lines = self._command(frame.hex().upper())
                    finally:
                        self._expect_ok(f"ATST{self._st:02X}")
                if st_min:
                    time.sleep(st_min / 1000)
                if block_end:
                    fc = self._read_flow_control(lines, rx_id, reasm)
                    if fc is None:
                        return
                    block_size, st_min = fc
                    sent_in_block = 0
                else:
                    sent_in_block += 1
                    self._parse_into(lines, reasm)
            if reasm.incomplete:
                raise ProtocolError("ECU sent a multi-frame reply, which ELM327 cannot receive in this mode")
        finally:
            self._expect_ok("ATCAF1")

    def _read_flow_control(
        self, lines: list[str], rx_id: int, reasm: isotp.Reassembler
    ) -> tuple[int, int] | None:
        """Return (block size, STmin ms), or None if the ECU answered instead."""
        reasm.flow_control.pop(rx_id, None)
        self._parse_into(lines, reasm)
        fc = reasm.flow_control.get(rx_id)
        if not fc:
            if reasm.messages:  # ECU rejected the request outright (e.g. 7F xx 13)
                return None
            raise NoResponseError("ECU did not send ISO-TP flow control")
        if fc[0] == 0x32:
            raise ProtocolError("ECU reported ISO-TP overflow (request too long)")
        if fc[0] != 0x30:
            raise ProtocolError(f"unsupported flow control {fc.hex()}")
        st = fc[2] if fc[2] <= 0x7F else 1
        return fc[1], st
