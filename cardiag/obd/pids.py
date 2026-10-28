"""SAE J1979 mode 01 / 02 parameter IDs and their decoders."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from ..errors import CarDiagError


class UnknownPIDError(CarDiagError, KeyError):
    def __str__(self) -> str:
        return self.args[0]


@dataclass(frozen=True)
class PID:
    pid: int
    name: str
    description: str
    unit: str
    length: int
    decode: Callable[[bytes], object]


def _u16(d: bytes) -> int:
    return (d[0] << 8) | d[1]


def _pct(d: bytes) -> float:
    return round(d[0] * 100 / 255, 1)


def _trim(d: bytes) -> float:
    return round((d[0] - 128) * 100 / 128, 1)


def _temp(d: bytes) -> int:
    return d[0] - 40


def _monitor_status(d: bytes) -> dict:
    return {"mil_on": bool(d[0] & 0x80), "dtc_count": d[0] & 0x7F, "compression_ignition": bool(d[1] & 0x08)}


_FUEL_SYSTEM = {
    0: "off",
    1: "open loop (cold)",
    2: "closed loop",
    4: "open loop (load/decel)",
    8: "open loop (fault)",
    16: "closed loop (fault)",
}

_PIDS = [
    PID(0x01, "monitor_status", "Monitor status since DTCs cleared", "", 4, _monitor_status),
    PID(0x03, "fuel_system", "Fuel system status", "", 2, lambda d: _FUEL_SYSTEM.get(d[0], f"0x{d[0]:02X}")),
    PID(0x04, "engine_load", "Calculated engine load", "%", 1, _pct),
    PID(0x05, "coolant_temp", "Engine coolant temperature", "°C", 1, _temp),
    PID(0x06, "stft_b1", "Short term fuel trim, bank 1", "%", 1, _trim),
    PID(0x07, "ltft_b1", "Long term fuel trim, bank 1", "%", 1, _trim),
    PID(0x08, "stft_b2", "Short term fuel trim, bank 2", "%", 1, _trim),
    PID(0x09, "ltft_b2", "Long term fuel trim, bank 2", "%", 1, _trim),
    PID(0x0A, "fuel_pressure", "Fuel pressure (gauge)", "kPa", 1, lambda d: d[0] * 3),
    PID(0x0B, "intake_map", "Intake manifold absolute pressure", "kPa", 1, lambda d: d[0]),
    PID(0x0C, "rpm", "Engine speed", "rpm", 2, lambda d: _u16(d) / 4),
    PID(0x0D, "speed", "Vehicle speed", "km/h", 1, lambda d: d[0]),
    PID(0x0E, "timing_advance", "Timing advance", "° BTDC", 1, lambda d: d[0] / 2 - 64),
    PID(0x0F, "intake_temp", "Intake air temperature", "°C", 1, _temp),
    PID(0x10, "maf", "Mass air flow rate", "g/s", 2, lambda d: _u16(d) / 100),
    PID(0x11, "throttle", "Throttle position", "%", 1, _pct),
    PID(0x1F, "run_time", "Run time since engine start", "s", 2, _u16),
    PID(0x21, "distance_mil", "Distance traveled with MIL on", "km", 2, _u16),
    PID(0x2F, "fuel_level", "Fuel tank level", "%", 1, _pct),
    PID(0x30, "warmups_since_clear", "Warm-ups since codes cleared", "", 1, lambda d: d[0]),
    PID(0x31, "distance_since_clear", "Distance since codes cleared", "km", 2, _u16),
    PID(0x33, "baro_pressure", "Barometric pressure", "kPa", 1, lambda d: d[0]),
    PID(0x42, "module_voltage", "Control module voltage", "V", 2, lambda d: _u16(d) / 1000),
    PID(0x43, "absolute_load", "Absolute load value", "%", 2, lambda d: round(_u16(d) * 100 / 255, 1)),
    PID(0x45, "relative_throttle", "Relative throttle position", "%", 1, _pct),
    PID(0x46, "ambient_temp", "Ambient air temperature", "°C", 1, _temp),
    PID(0x49, "accel_pedal_d", "Accelerator pedal position D", "%", 1, _pct),
    PID(0x4D, "time_with_mil", "Time run with MIL on", "min", 2, _u16),
    PID(0x4E, "time_since_clear", "Time since codes cleared", "min", 2, _u16),
    PID(0x5C, "oil_temp", "Engine oil temperature", "°C", 1, _temp),
    PID(0x5E, "fuel_rate", "Engine fuel rate", "L/h", 2, lambda d: _u16(d) / 20),
]

BY_NUMBER: dict[int, PID] = {p.pid: p for p in _PIDS}
BY_NAME: dict[str, PID] = {p.name: p for p in _PIDS}


def lookup(key: str | int) -> PID:
    """Find a PID by name (``rpm``) or number (``0x0C``, ``12``, ``0C``)."""
    if isinstance(key, int):
        if key in BY_NUMBER:
            return BY_NUMBER[key]
        raise UnknownPIDError(f"unknown PID 0x{key:02X}")
    if key.lower() in BY_NAME:
        return BY_NAME[key.lower()]
    try:
        num = int(key, 16)
    except ValueError:
        raise UnknownPIDError(f"unknown PID {key!r} (see 'cardiag pids')") from None
    return lookup(num)


def all_pids() -> list[PID]:
    return list(_PIDS)


def decode_supported(base: int, data: bytes) -> set[int]:
    """Decode a 'PIDs supported [base+1 - base+0x20]' bitmap."""
    bits = int.from_bytes(data[:4], "big")
    return {base + i + 1 for i in range(32) if bits & (1 << (31 - i))}
