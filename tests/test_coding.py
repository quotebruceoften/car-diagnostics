import json

import pytest

from cardiag.coding import Coder, Profile, available_profiles, find_profile
from cardiag.errors import CodingError
from cardiag.sim import ELM327Emulator


@pytest.fixture
def profile():
    return find_profile("demo_bcm")


def test_builtin_profiles_load():
    assert "demo_bcm" in available_profiles()


def test_decode_and_apply(profile):
    data = bytes([0x15, 0x03, 0x1E, 0, 0, 0, 0, 0])
    decoded = profile.decode(data)
    assert decoded["drl"] == "on"
    assert decoded["auto_lock"] == "15 km/h"
    assert decoded["comfort_blinks"] == "3"
    assert decoded["coming_home"] == "30 s"
    assert decoded["region"] == "EU"
    new = profile.apply(data, {"drl": "off", "auto_lock": "25 km/h", "region": "us", "coming_home": "60"})
    assert new == bytes([0x16, 0x03, 0x3C, 0x01, 0, 0, 0, 0])


def test_apply_preserves_unmapped_bits(profile):
    data = bytes([0xC0 | 0x01, 0xF8 | 0x03, 0, 0xFC, 0xAA, 0, 0, 0])
    new = profile.apply(data, {"drl": "off", "comfort_blinks": "7", "region": "ROW"})
    assert new == bytes([0xC0, 0xFF, 0, 0xFE, 0xAA, 0, 0, 0])


@pytest.mark.parametrize(
    "change", [{"drl": "maybe"}, {"comfort_blinks": "0"}, {"region": "MARS"}, {"nope": "1"}]
)
def test_invalid_values_rejected(profile, change):
    with pytest.raises(CodingError):
        profile.apply(bytes(8), change)


def test_wrong_length_rejected(profile):
    with pytest.raises(CodingError):
        profile.decode(bytes(4))


@pytest.mark.parametrize(
    "option",
    [
        {"key": "x", "byte": 9, "bit": 0},
        {"key": "x", "byte": 0, "bit": 6, "width": 3, "type": "int"},
        {"key": "x", "byte": 0, "bit": 0, "width": 2, "type": "bool"},
        {"key": "x", "byte": 0, "type": "enum"},
        {"key": "x", "byte": 0, "type": "float"},
    ],
)
def test_bad_profiles_rejected(option):
    with pytest.raises(CodingError):
        Profile.from_dict({"id": "t", "tx_id": "0x700", "did": "0x0100", "length": 2, "options": [option]})


def test_write_verifies_and_backs_up(transport, profile, cardiag_home):
    coder = Coder(transport, profile)
    old = coder.read()
    new = profile.apply(old, {"drl": "off", "comfort_blinks": "5"})
    result = coder.write(new)
    assert coder.read() == new
    record = json.loads(result.backup.read_text())
    assert bytes.fromhex(record["data"]) == old
    assert record["vin"] == "WVWZZZ1KZ8W123456"
    assert result.backup.parent == cardiag_home / "backups"
    # Restoring the backup brings the original coding back.
    coder.write(coder.load_backup(result.backup))
    assert coder.read() == old


def test_multiframe_write_through_elm(vehicle, profile):
    """An 11-byte WriteDataByIdentifier needs manual ISO-TP on an ELM327."""
    from cardiag.transport.elm327 import ELM327Transport

    emu = ELM327Emulator(vehicle)
    coder = Coder(ELM327Transport(emu), profile)
    new = profile.apply(coder.read(), {"region": "ROW"})
    coder.write(new)
    assert vehicle.ecu(0x726).dids[0x0600] == new
    assert "ATCAF0" in emu.log and emu.log[-1] != "ATCAF0"
    assert any(cmd.startswith("100B2E0600") for cmd in emu.log)


def test_wrong_algorithm_fails_cleanly(transport, profile):
    import dataclasses

    bad = dataclasses.replace(profile, security_algorithm="does_not_exist")
    coder = Coder(transport, bad)
    with pytest.raises(CodingError):
        coder.write(profile.apply(coder.read(), {"drl": "off"}))


def test_backup_for_other_profile_rejected(transport, profile, tmp_path):
    path = tmp_path / "b.json"
    path.write_text(json.dumps({"profile": "other", "data": "00" * 8}))
    with pytest.raises(CodingError):
        Coder(transport, profile).load_backup(path)
