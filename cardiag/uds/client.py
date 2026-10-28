"""Unified Diagnostic Services (ISO 14229-1) client."""
from __future__ import annotations

from typing import Callable

from ..errors import CarDiagError, NoResponseError, ProtocolError
from ..obd.dtc import DTC, decode as decode_dtc
from ..transport.base import Transport

NRC_NAMES = {
    0x10: "generalReject",
    0x11: "serviceNotSupported",
    0x12: "subFunctionNotSupported",
    0x13: "incorrectMessageLengthOrInvalidFormat",
    0x14: "responseTooLong",
    0x21: "busyRepeatRequest",
    0x22: "conditionsNotCorrect",
    0x24: "requestSequenceError",
    0x25: "noResponseFromSubnetComponent",
    0x26: "failurePreventsExecutionOfRequestedAction",
    0x31: "requestOutOfRange",
    0x33: "securityAccessDenied",
    0x35: "invalidKey",
    0x36: "exceededNumberOfAttempts",
    0x37: "requiredTimeDelayNotExpired",
    0x70: "uploadDownloadNotAccepted",
    0x72: "generalProgrammingFailure",
    0x78: "requestCorrectlyReceived-ResponsePending",
    0x7E: "subFunctionNotSupportedInActiveSession",
    0x7F: "serviceNotSupportedInActiveSession",
}

# Standard identification DIDs (ISO 14229-1 Annex C).
STANDARD_DIDS = {
    0xF186: "Active diagnostic session",
    0xF187: "Spare part number",
    0xF188: "ECU software number",
    0xF189: "ECU software version",
    0xF18A: "System supplier ID",
    0xF18B: "ECU manufacturing date",
    0xF18C: "ECU serial number",
    0xF190: "VIN",
    0xF191: "ECU hardware number",
    0xF192: "Supplier hardware number",
    0xF193: "Supplier hardware version",
    0xF194: "Supplier software number",
    0xF195: "Supplier software version",
    0xF197: "System name",
    0xF19E: "ODX file",
}

DEFAULT_SESSION = 0x01
PROGRAMMING_SESSION = 0x02
EXTENDED_SESSION = 0x03

KeyFunction = Callable[[bytes, int], bytes]


class NegativeResponseError(CarDiagError):
    def __init__(self, service: int, nrc: int) -> None:
        self.service = service
        self.nrc = nrc
        name = NRC_NAMES.get(nrc, "unknown")
        super().__init__(f"service 0x{service:02X} rejected: NRC 0x{nrc:02X} ({name})")


def format_did_value(data: bytes) -> str:
    """Show printable identifiers as text, everything else as hex."""
    stripped = data.rstrip(b"\x00 ")
    if stripped and all(32 <= b < 127 for b in stripped):
        return stripped.decode("ascii")
    return data.hex(" ").upper()


class UDSClient:
    def __init__(self, transport: Transport, tx_id: int, rx_id: int | None = None) -> None:
        self.transport = transport
        self.tx_id = tx_id
        self.rx_id = rx_id if rx_id is not None else tx_id + 8

    def request(self, payload: bytes) -> bytes:
        """Send a request and return the positive response (including its SID)."""
        sid = payload[0]
        replies = [m.data for m in self.transport.send(self.tx_id, payload, self.rx_id) if m.rx_id == self.rx_id]
        # "Response pending" (NRC 0x78) precedes the real answer; drop it.
        final = [r for r in replies if not (len(r) >= 3 and r[0] == 0x7F and r[2] == 0x78)]
        if not final:
            if replies:
                raise NoResponseError(f"ECU 0x{self.tx_id:X} still busy (response pending) - retry later")
            raise NoResponseError(f"no response from ECU 0x{self.tx_id:X}")
        reply = final[-1]
        if reply[0] == 0x7F:
            if len(reply) < 3:
                raise ProtocolError(f"malformed negative response {reply.hex()}")
            raise NegativeResponseError(reply[1], reply[2])
        if reply[0] != sid + 0x40:
            raise ProtocolError(f"unexpected reply {reply.hex()} to service 0x{sid:02X}")
        return reply

    # -------------------------------------------------------------- services
    def diagnostic_session_control(self, session: int) -> bytes:
        return self.request(bytes([0x10, session]))[2:]

    def ecu_reset(self, reset_type: int = 0x01) -> None:
        self.request(bytes([0x11, reset_type]))

    def tester_present(self) -> None:
        self.request(b"\x3E\x00")

    def read_data_by_identifier(self, did: int) -> bytes:
        reply = self.request(bytes([0x22, did >> 8, did & 0xFF]))
        if reply[1:3] != bytes([did >> 8, did & 0xFF]):
            raise ProtocolError(f"reply for wrong DID: {reply.hex()}")
        return reply[3:]

    def write_data_by_identifier(self, did: int, data: bytes) -> None:
        self.request(bytes([0x2E, did >> 8, did & 0xFF]) + bytes(data))

    def security_access(self, level: int, key_function: KeyFunction) -> None:
        """Unlock security ``level`` (odd number) using ``key_function(seed, level)``."""
        if level % 2 == 0:
            raise ValueError("security access level must be odd (the seed request)")
        seed = self.request(bytes([0x27, level]))[2:]
        if not any(seed):
            return  # already unlocked
        key = key_function(seed, level)
        self.request(bytes([0x27, level + 1]) + bytes(key))

    def read_dtcs(self, status_mask: int = 0xFF) -> list[DTC]:
        """ReadDTCInformation, reportDTCByStatusMask."""
        reply = self.request(bytes([0x19, 0x02, status_mask]))
        body = reply[3:]  # skip SID, sub-function, availability mask
        dtcs = []
        for i in range(0, len(body) - 3, 4):
            rec = body[i : i + 4]
            dtcs.append(DTC(decode_dtc(rec[:2]), status=rec[3], failure_type=rec[2]))
        return dtcs

    def clear_dtcs(self, group: int = 0xFFFFFF) -> None:
        self.request(bytes([0x14, (group >> 16) & 0xFF, (group >> 8) & 0xFF, group & 0xFF]))

    def identify(self) -> dict[int, bytes]:
        """Read every standard identification DID the ECU supports."""
        info = {}
        for did in STANDARD_DIDS:
            try:
                info[did] = self.read_data_by_identifier(did)
            except (NegativeResponseError, NoResponseError):
                continue
        return info
