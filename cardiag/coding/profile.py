"""Coding profiles: describe how a module's coding block maps to named options.

A profile is a JSON file::

    {
      "id": "demo_bcm",
      "name": "Demo body control module",
      "tx_id": "0x726", "rx_id": "0x72E",
      "session": "0x03",
      "security": {"level": 1, "algorithm": "demo_xor"},
      "did": "0x0600",
      "length": 8,
      "options": [
        {"key": "drl", "label": "Daytime running lights",
         "byte": 0, "bit": 0, "type": "bool"},
        {"key": "comfort_blinks", "label": "Comfort turn signal flashes",
         "byte": 1, "bit": 0, "width": 3, "type": "int", "min": 1, "max": 7},
        {"key": "region", "label": "Market", "byte": 3, "bit": 0, "width": 2,
         "type": "enum", "values": {"0": "EU", "1": "US", "2": "ROW"}}
      ]
    }

``bit`` is the least significant bit of the field (0 = LSB) and a field must
fit inside its byte. Bits not covered by any option are never changed.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

from ..errors import CodingError

_TRUE = {"1", "on", "true", "yes", "enable", "enabled"}
_FALSE = {"0", "off", "false", "no", "disable", "disabled"}


def _int(value) -> int:
    return value if isinstance(value, int) else int(str(value), 0)


@dataclass(frozen=True)
class Option:
    key: str
    label: str
    byte: int
    bit: int
    width: int
    type: str
    values: dict[int, str] = field(default_factory=dict)
    min: int = 0
    max: int = 0
    unit: str = ""

    @property
    def mask(self) -> int:
        return ((1 << self.width) - 1) << self.bit

    def raw(self, data: bytes) -> int:
        return (data[self.byte] & self.mask) >> self.bit

    def display(self, data: bytes) -> str:
        raw = self.raw(data)
        if self.type == "bool":
            return "on" if raw else "off"
        if self.type == "enum":
            return self.values.get(raw, f"unknown ({raw})")
        return f"{raw} {self.unit}".strip()

    def parse(self, text: str) -> int:
        """Convert a user-supplied value into the raw field value."""
        t = str(text).strip().lower()
        if self.type == "bool":
            if t in _TRUE:
                return 1
            if t in _FALSE:
                return 0
            raise CodingError(f"{self.key}: expected on/off, got {text!r}")
        if self.type == "enum":
            for raw, label in self.values.items():
                if label.lower() == t:
                    return raw
            try:
                raw = int(t, 0)
            except ValueError:
                raw = None
            if raw in self.values:
                return raw
            choices = ", ".join(self.values.values())
            raise CodingError(f"{self.key}: expected one of {choices}, got {text!r}")
        try:
            raw = int(t, 0)
        except ValueError:
            raise CodingError(f"{self.key}: expected a number, got {text!r}") from None
        if not self.min <= raw <= self.max:
            raise CodingError(f"{self.key}: {raw} is outside {self.min}..{self.max}")
        return raw

    def apply(self, data: bytearray, raw: int) -> None:
        data[self.byte] = (data[self.byte] & ~self.mask & 0xFF) | ((raw << self.bit) & self.mask)

    def describe_range(self) -> str:
        if self.type == "bool":
            return "on/off"
        if self.type == "enum":
            return " | ".join(self.values.values())
        return f"{self.min}..{self.max}{' ' + self.unit if self.unit else ''}"


@dataclass(frozen=True)
class Profile:
    id: str
    name: str
    tx_id: int
    rx_id: int
    did: int
    length: int
    options: tuple[Option, ...]
    session: int = 0x03
    security_level: int | None = None
    security_algorithm: str | None = None
    description: str = ""
    source: str = ""

    def option(self, key: str) -> Option:
        for opt in self.options:
            if opt.key == key:
                return opt
        raise CodingError(f"profile {self.id!r} has no option {key!r} (see 'coding show')")

    def decode(self, data: bytes) -> dict[str, str]:
        self._check_length(data)
        return {o.key: o.display(data) for o in self.options}

    def apply(self, data: bytes, changes: dict[str, str]) -> bytes:
        """Return a copy of ``data`` with the named options changed."""
        self._check_length(data)
        out = bytearray(data)
        for key, value in changes.items():
            opt = self.option(key)
            opt.apply(out, opt.parse(value))
        return bytes(out)

    def _check_length(self, data: bytes) -> None:
        if len(data) != self.length:
            raise CodingError(
                f"coding block is {len(data)} bytes but profile {self.id!r} expects {self.length}"
                " - wrong module or profile?"
            )

    # -------------------------------------------------------------- loading
    @classmethod
    def from_dict(cls, d: dict, source: str = "") -> "Profile":
        try:
            length = int(d["length"])
            options = []
            seen = set()
            for o in d["options"]:
                kind = o.get("type", "bool")
                width = int(o.get("width", 1))
                opt = Option(
                    key=o["key"],
                    label=o.get("label", o["key"]),
                    byte=int(o["byte"]),
                    bit=int(o.get("bit", 0)),
                    width=width,
                    type=kind,
                    values={int(k, 0): v for k, v in o.get("values", {}).items()},
                    min=int(o.get("min", 0)),
                    max=int(o.get("max", (1 << width) - 1)),
                    unit=o.get("unit", ""),
                )
                if kind not in ("bool", "enum", "int"):
                    raise CodingError(f"option {opt.key}: unknown type {kind!r}")
                if kind == "bool" and width != 1:
                    raise CodingError(f"option {opt.key}: bool options must be 1 bit wide")
                if kind == "enum" and not opt.values:
                    raise CodingError(f"option {opt.key}: enum options need 'values'")
                if not 0 <= opt.byte < length or opt.bit < 0 or opt.bit + width > 8:
                    raise CodingError(f"option {opt.key}: field does not fit in byte {opt.byte}")
                if kind == "int" and not 0 <= opt.min <= opt.max < (1 << width):
                    raise CodingError(f"option {opt.key}: min/max do not fit in {width} bits")
                if opt.key in seen:
                    raise CodingError(f"duplicate option key {opt.key!r}")
                seen.add(opt.key)
                options.append(opt)
            security = d.get("security") or {}
            return cls(
                id=d["id"],
                name=d.get("name", d["id"]),
                description=d.get("description", ""),
                tx_id=_int(d["tx_id"]),
                rx_id=_int(d.get("rx_id", _int(d["tx_id"]) + 8)),
                did=_int(d["did"]),
                length=length,
                session=_int(d.get("session", 0x03)),
                security_level=_int(security["level"]) if security else None,
                security_algorithm=security.get("algorithm") if security else None,
                options=tuple(options),
                source=source,
            )
        except KeyError as exc:
            raise CodingError(f"profile {source or '?'} is missing field {exc}") from None
        except (TypeError, ValueError) as exc:
            raise CodingError(f"profile {source or '?'} is invalid: {exc}") from None

    @classmethod
    def load(cls, path: str | Path) -> "Profile":
        path = Path(path)
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            raise CodingError(f"cannot read profile {path}: {exc}") from exc
        return cls.from_dict(data, source=str(path))


def home_dir() -> Path:
    return Path(os.environ.get("CARDIAG_HOME", Path.home() / ".cardiag"))


def profile_dirs() -> list[Path]:
    return [Path(__file__).parent / "profiles", home_dir() / "profiles"]


def available_profiles() -> dict[str, Profile]:
    """Built-in profiles plus any in ``$CARDIAG_HOME/profiles`` (user ones win)."""
    found: dict[str, Profile] = {}
    for d in profile_dirs():
        if d.is_dir():
            for path in sorted(d.glob("*.json")):
                profile = Profile.load(path)
                found[profile.id] = profile
    return found


def find_profile(name: str) -> Profile:
    """Find a profile by id, or load it from a file path."""
    if name.endswith(".json") or os.sep in name:
        return Profile.load(name)
    profiles = available_profiles()
    if name not in profiles:
        known = ", ".join(sorted(profiles)) or "none"
        raise CodingError(f"no coding profile {name!r} (available: {known})")
    return profiles[name]
