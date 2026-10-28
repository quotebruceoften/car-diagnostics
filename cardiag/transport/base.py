from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

# Functional (broadcast) request ID for OBD-II on 11-bit CAN.
OBD_BROADCAST_ID = 0x7DF


@dataclass(frozen=True)
class Message:
    """A complete (ISO-TP reassembled) diagnostic message received from an ECU."""

    rx_id: int
    data: bytes

    def __repr__(self) -> str:
        return f"Message(rx_id=0x{self.rx_id:X}, data={self.data.hex(' ').upper()})"


class Transport(ABC):
    """Sends a diagnostic payload to a CAN ID and collects the replies.

    Implementations hide adapter details and ISO-TP segmentation: callers
    deal only in whole application-layer payloads.
    """

    @abstractmethod
    def send(self, tx_id: int, payload: bytes, rx_id: int | None = None) -> list[Message]:
        """Send ``payload`` to ``tx_id`` and return every reply received.

        ``rx_id`` restricts replies to a single ECU; ``None`` accepts all
        (used for OBD broadcast requests).
        """

    def close(self) -> None:  # pragma: no cover - default no-op
        pass

    @property
    def description(self) -> str:
        return type(self).__name__

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
