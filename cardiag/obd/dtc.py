"""Diagnostic trouble code encoding/decoding and descriptions."""
from __future__ import annotations

from dataclasses import dataclass

_SYSTEMS = "PCBU"

# Generic (SAE J2012) descriptions for the most common codes. Manufacturer
# specific codes (second character 1 or 3) fall back to a generic label.
DESCRIPTIONS = {
    "P0010": "Camshaft position actuator circuit (bank 1)",
    "P0011": "Camshaft position timing over-advanced (bank 1)",
    "P0016": "Crankshaft/camshaft position correlation (bank 1 sensor A)",
    "P0030": "HO2S heater control circuit (bank 1 sensor 1)",
    "P0100": "Mass air flow circuit malfunction",
    "P0101": "Mass air flow circuit range/performance",
    "P0102": "Mass air flow circuit low input",
    "P0106": "MAP/barometric pressure circuit range/performance",
    "P0110": "Intake air temperature circuit malfunction",
    "P0115": "Engine coolant temperature circuit malfunction",
    "P0117": "Engine coolant temperature circuit low input",
    "P0118": "Engine coolant temperature circuit high input",
    "P0120": "Throttle position sensor circuit malfunction",
    "P0121": "Throttle position sensor circuit range/performance",
    "P0128": "Coolant thermostat (temperature below regulating temperature)",
    "P0130": "O2 sensor circuit malfunction (bank 1 sensor 1)",
    "P0131": "O2 sensor circuit low voltage (bank 1 sensor 1)",
    "P0133": "O2 sensor circuit slow response (bank 1 sensor 1)",
    "P0135": "O2 sensor heater circuit malfunction (bank 1 sensor 1)",
    "P0141": "O2 sensor heater circuit malfunction (bank 1 sensor 2)",
    "P0171": "System too lean (bank 1)",
    "P0172": "System too rich (bank 1)",
    "P0174": "System too lean (bank 2)",
    "P0175": "System too rich (bank 2)",
    "P0200": "Injector circuit malfunction",
    "P0217": "Engine overtemperature condition",
    "P0230": "Fuel pump primary circuit malfunction",
    "P0300": "Random/multiple cylinder misfire detected",
    "P0301": "Cylinder 1 misfire detected",
    "P0302": "Cylinder 2 misfire detected",
    "P0303": "Cylinder 3 misfire detected",
    "P0304": "Cylinder 4 misfire detected",
    "P0305": "Cylinder 5 misfire detected",
    "P0306": "Cylinder 6 misfire detected",
    "P0325": "Knock sensor 1 circuit malfunction",
    "P0335": "Crankshaft position sensor A circuit malfunction",
    "P0340": "Camshaft position sensor circuit malfunction",
    "P0351": "Ignition coil A primary/secondary circuit malfunction",
    "P0400": "Exhaust gas recirculation flow malfunction",
    "P0401": "Exhaust gas recirculation flow insufficient",
    "P0402": "Exhaust gas recirculation flow excessive",
    "P0410": "Secondary air injection system malfunction",
    "P0420": "Catalyst system efficiency below threshold (bank 1)",
    "P0430": "Catalyst system efficiency below threshold (bank 2)",
    "P0440": "Evaporative emission control system malfunction",
    "P0441": "EVAP system incorrect purge flow",
    "P0442": "EVAP system leak detected (small leak)",
    "P0446": "EVAP vent control circuit malfunction",
    "P0455": "EVAP system leak detected (large leak)",
    "P0456": "EVAP system leak detected (very small leak)",
    "P0500": "Vehicle speed sensor malfunction",
    "P0505": "Idle control system malfunction",
    "P0506": "Idle control system RPM lower than expected",
    "P0507": "Idle control system RPM higher than expected",
    "P0562": "System voltage low",
    "P0563": "System voltage high",
    "P0600": "Serial communication link malfunction",
    "P0700": "Transmission control system malfunction",
    "P0715": "Input/turbine speed sensor circuit malfunction",
    "P0720": "Output speed sensor circuit malfunction",
    "P0730": "Incorrect gear ratio",
    "P0740": "Torque converter clutch circuit malfunction",
    "P0750": "Shift solenoid A malfunction",
    "U0100": "Lost communication with ECM/PCM A",
    "U0101": "Lost communication with TCM",
    "U0121": "Lost communication with ABS control module",
    "U0140": "Lost communication with body control module",
    "U0155": "Lost communication with instrument panel cluster",
    "B1000": "ECU malfunction (body)",
    "C0035": "Left front wheel speed sensor circuit",
    "C0040": "Right front wheel speed sensor circuit",
}

_SYSTEM_NAMES = {"P": "Powertrain", "C": "Chassis", "B": "Body", "U": "Network"}


@dataclass(frozen=True)
class DTC:
    code: str
    status: int | None = None  # UDS status byte, if known
    failure_type: int | None = None  # UDS failure type byte (3-byte DTCs)

    @property
    def description(self) -> str:
        return describe(self.code)

    @property
    def display(self) -> str:
        return self.code if self.failure_type is None else f"{self.code}-{self.failure_type:02X}"

    def status_flags(self) -> list[str]:
        if self.status is None:
            return []
        return [name for bit, name in _STATUS_BITS if self.status & bit]


_STATUS_BITS = [
    (0x01, "testFailed"),
    (0x02, "testFailedThisCycle"),
    (0x04, "pending"),
    (0x08, "confirmed"),
    (0x10, "testNotCompletedSinceClear"),
    (0x20, "testFailedSinceClear"),
    (0x40, "testNotCompletedThisCycle"),
    (0x80, "warningIndicator"),
]


def decode(two_bytes: bytes) -> str:
    """Decode a 2-byte SAE J2012 DTC into its 5-character form (e.g. P0301)."""
    a, b = two_bytes[0], two_bytes[1]
    return f"{_SYSTEMS[a >> 6]}{(a >> 4) & 0x3}{a & 0xF:X}{b:02X}"


def encode(code: str) -> bytes:
    """Encode a 5-character DTC (e.g. P0301) into its 2-byte form."""
    code = code.strip().upper()
    if len(code) != 5 or code[0] not in _SYSTEMS or code[1] not in "0123":
        raise ValueError(f"invalid DTC {code!r}")
    a = (_SYSTEMS.index(code[0]) << 6) | (int(code[1]) << 4) | int(code[2], 16)
    return bytes([a, int(code[3:], 16)])


def describe(code: str) -> str:
    if code in DESCRIPTIONS:
        return DESCRIPTIONS[code]
    system = _SYSTEM_NAMES.get(code[:1], "Unknown")
    kind = "manufacturer specific" if code[1:2] in ("1", "3") else "generic"
    return f"{system} fault ({kind}, no description available)"


def parse_obd_response(data: bytes) -> list[DTC]:
    """Parse the body of a mode 03/07/0A response (after the 0x43/0x47/0x4A byte).

    On CAN the first byte is the number of DTCs; pairs of 0x0000 are padding.
    """
    if not data:
        return []
    count, body = data[0], data[1:]
    codes = []
    for i in range(0, min(len(body), count * 2), 2):
        pair = body[i : i + 2]
        if len(pair) == 2 and pair != b"\x00\x00":
            codes.append(DTC(decode(pair)))
    return codes
