import pytest

from cardiag.errors import ProtocolError
from cardiag.obd import dtc, pids
from cardiag.transport import isotp


@pytest.mark.parametrize("length", [1, 7, 8, 13, 20, 100])
def test_segment_reassemble_roundtrip(length):
    payload = bytes(range(length))
    frames = isotp.segment(payload)
    assert all(len(f) == 8 for f in frames)
    r = isotp.Reassembler()
    for f in frames:
        r.feed(0x7E8, f)
    assert r.messages == [(0x7E8, payload)]
    assert not r.incomplete


def test_reassembler_interleaved_ecus():
    a, b = bytes(range(20)), bytes(range(100, 115))
    fa, fb = isotp.segment(a), isotp.segment(b)
    r = isotp.Reassembler()
    for x, y in zip(fa, fb):
        r.feed(0x7E8, x)
        r.feed(0x7E9, y)
    for x in fa[len(fb):]:
        r.feed(0x7E8, x)
    assert sorted(r.messages) == [(0x7E8, a), (0x7E9, b)]


def test_reassembler_sequence_error():
    frames = isotp.segment(bytes(20))
    r = isotp.Reassembler()
    r.feed(0x7E8, frames[0])
    with pytest.raises(ProtocolError):
        r.feed(0x7E8, frames[2])


@pytest.mark.parametrize("code", ["P0301", "P0420", "C0035", "B1000", "U0155", "P2AF1", "U3FFF"])
def test_dtc_roundtrip(code):
    assert dtc.decode(dtc.encode(code)) == code


def test_dtc_known_bytes():
    assert dtc.decode(b"\x01\x33") == "P0133"
    assert dtc.decode(b"\xC1\x55") == "U0155"


def test_dtc_parse_skips_padding():
    codes = dtc.parse_obd_response(bytes([2, 0x03, 0x01, 0x04, 0x20, 0, 0]))
    assert [c.code for c in codes] == ["P0301", "P0420"]


def test_dtc_descriptions():
    assert "misfire" in dtc.describe("P0301").lower()
    assert "manufacturer specific" in dtc.describe("P1234")


def test_pid_decoding():
    assert pids.lookup("rpm").decode(bytes([0x1A, 0xF8])) == 1726.0
    assert pids.lookup("0x05").decode(bytes([0x7B])) == 83
    assert pids.lookup(0x06).decode(bytes([0x80])) == 0.0
    assert pids.lookup("0D").name == "speed"
    with pytest.raises(KeyError):
        pids.lookup("nope")


def test_supported_bitmap():
    assert pids.decode_supported(0, bytes([0xBE, 0x1F, 0xA8, 0x13])) == {
        0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20
    }
