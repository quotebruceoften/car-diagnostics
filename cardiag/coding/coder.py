"""Reading and writing a module's coding block, with backups and verification."""
from __future__ import annotations

import json
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from ..errors import CodingError, NoResponseError
from ..transport.base import Transport
from ..uds import DEFAULT_SESSION, NegativeResponseError, UDSClient
from . import security
from .profile import Profile, home_dir


@dataclass(frozen=True)
class WriteResult:
    old: bytes
    new: bytes
    backup: Path


class Coder:
    def __init__(self, transport: Transport, profile: Profile, backup_dir: Path | None = None) -> None:
        self.profile = profile
        self.uds = UDSClient(transport, profile.tx_id, profile.rx_id)
        self.backup_dir = backup_dir or home_dir() / "backups"

    def read(self) -> bytes:
        data = self.uds.read_data_by_identifier(self.profile.did)
        if len(data) != self.profile.length:
            raise CodingError(
                f"module returned {len(data)} coding bytes, profile expects {self.profile.length}"
                " - wrong module or profile?"
            )
        return data

    def backup(self, data: bytes | None = None) -> Path:
        """Save the current coding block to a timestamped JSON file."""
        if data is None:
            data = self.read()
        try:
            vin = self.uds.read_data_by_identifier(0xF190).decode("ascii", errors="replace")
        except (NegativeResponseError, NoResponseError):
            vin = ""
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        path = self.backup_dir / f"{self.profile.id}-{stamp}.json"
        record = {
            "profile": self.profile.id,
            "tx_id": f"0x{self.profile.tx_id:X}",
            "did": f"0x{self.profile.did:04X}",
            "vin": vin,
            "timestamp": stamp,
            "data": data.hex().upper(),
            "decoded": self.profile.decode(data),
        }
        path.write_text(json.dumps(record, indent=2) + "\n")
        return path

    def load_backup(self, path: str | Path) -> bytes:
        try:
            record = json.loads(Path(path).read_text())
            data = bytes.fromhex(record["data"])
        except (OSError, ValueError, KeyError) as exc:
            raise CodingError(f"invalid backup file {path}: {exc}") from exc
        if record.get("profile") != self.profile.id:
            raise CodingError(f"backup is for profile {record.get('profile')!r}, not {self.profile.id!r}")
        if len(data) != self.profile.length:
            raise CodingError("backup length does not match the profile")
        return data

    def unlock(self) -> None:
        """Enter the profile's diagnostic session and pass security access if needed."""
        self.uds.diagnostic_session_control(self.profile.session)
        if self.profile.security_level is not None:
            if not self.profile.security_algorithm:
                raise CodingError("profile requires security access but names no algorithm")
            key_fn = security.get(self.profile.security_algorithm)
            self.uds.security_access(self.profile.security_level, key_fn)

    def write(self, new: bytes) -> WriteResult:
        """Back up the current coding, write ``new``, and verify by reading it back."""
        if len(new) != self.profile.length:
            raise CodingError("new coding has the wrong length")
        old = self.read()
        backup = self.backup(old)
        if old == new:
            return WriteResult(old, new, backup)
        self.unlock()
        try:
            self.uds.write_data_by_identifier(self.profile.did, new)
            time.sleep(0.05)
            readback = self.read()
            if readback != new:
                raise CodingError(
                    f"verification failed: wrote {new.hex().upper()} but module reports "
                    f"{readback.hex().upper()}. Backup saved at {backup}"
                )
        finally:
            try:
                self.uds.diagnostic_session_control(DEFAULT_SESSION)
            except (NegativeResponseError, NoResponseError):
                pass  # the session times out by itself anyway
        return WriteResult(old, new, backup)
