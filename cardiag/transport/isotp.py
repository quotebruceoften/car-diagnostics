"""ISO 15765-2 (ISO-TP) framing helpers used by the ELM327 driver and emulator."""
from __future__ import annotations

from collections import defaultdict

from ..errors import ProtocolError


def segment(payload: bytes, pad: int = 0x00) -> list[bytes]:
    """Split a payload into 8-byte CAN frames (single or first+consecutive)."""
    if len(payload) <= 7:
        return [_pad(bytes([len(payload)]) + payload, pad)]
    if len(payload) > 0xFFF:
        raise ValueError("payload too long for ISO-TP")
    frames = [bytes([0x10 | (len(payload) >> 8), len(payload) & 0xFF]) + payload[:6]]
    rest, seq = payload[6:], 1
    while rest:
        frames.append(_pad(bytes([0x20 | (seq & 0x0F)]) + rest[:7], pad))
        rest, seq = rest[7:], seq + 1
    return frames


def _pad(frame: bytes, pad: int) -> bytes:
    return frame + bytes([pad]) * (8 - len(frame))


class Reassembler:
    """Reassembles raw CAN frames, possibly interleaved between ECUs."""

    def __init__(self) -> None:
        self._partial: dict[int, tuple[int, bytearray, int]] = {}
        self.messages: list[tuple[int, bytes]] = []
        self.flow_control: dict[int, bytes] = defaultdict(bytes)

    def feed(self, can_id: int, frame: bytes) -> None:
        if not frame:
            return
        kind = frame[0] >> 4
        if kind == 0x0:  # single frame
            length = frame[0] & 0x0F
            if length == 0 or length > len(frame) - 1:
                raise ProtocolError(f"bad single frame from 0x{can_id:X}: {frame.hex()}")
            self.messages.append((can_id, bytes(frame[1 : 1 + length])))
        elif kind == 0x1:  # first frame
            length = ((frame[0] & 0x0F) << 8) | frame[1]
            self._partial[can_id] = (length, bytearray(frame[2:]), 1)
        elif kind == 0x2:  # consecutive frame
            if can_id not in self._partial:
                raise ProtocolError(f"consecutive frame without first frame from 0x{can_id:X}")
            length, buf, expected = self._partial[can_id]
            if frame[0] & 0x0F != expected & 0x0F:
                raise ProtocolError(f"ISO-TP sequence error from 0x{can_id:X}")
            buf.extend(frame[1:])
            if len(buf) >= length:
                del self._partial[can_id]
                self.messages.append((can_id, bytes(buf[:length])))
            else:
                self._partial[can_id] = (length, buf, expected + 1)
        elif kind == 0x3:  # flow control
            self.flow_control[can_id] = bytes(frame[:3])
        else:
            raise ProtocolError(f"unknown ISO-TP frame type from 0x{can_id:X}: {frame.hex()}")

    @property
    def incomplete(self) -> bool:
        return bool(self._partial)
