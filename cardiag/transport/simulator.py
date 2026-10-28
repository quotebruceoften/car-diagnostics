from __future__ import annotations

from .base import Message, Transport, OBD_BROADCAST_ID


class SimulatorTransport(Transport):
    """Talks directly to a :class:`cardiag.sim.vehicle.Vehicle` (no adapter)."""

    def __init__(self, vehicle=None) -> None:
        if vehicle is None:
            from ..sim.vehicle import Vehicle

            vehicle = Vehicle.demo()
        self.vehicle = vehicle

    def send(self, tx_id: int, payload: bytes, rx_id: int | None = None) -> list[Message]:
        replies = self.vehicle.handle(tx_id, bytes(payload))
        return [Message(r, d) for r, d in replies if rx_id is None or r == rx_id]

    @property
    def description(self) -> str:
        return f"Simulator ({self.vehicle.name})"


__all__ = ["SimulatorTransport", "OBD_BROADCAST_ID"]
