import pytest

from cardiag.coding.security import demo_xor
from cardiag.errors import NoResponseError
from cardiag.uds import EXTENDED_SESSION, NegativeResponseError, UDSClient
from cardiag.transport.base import Message, Transport


def test_identify(transport):
    info = UDSClient(transport, 0x7E0).identify()
    assert info[0xF190] == b"WVWZZZ1KZ8W123456"
    assert info[0xF187] == b"06K907425B"


def test_negative_response(transport):
    uds = UDSClient(transport, 0x7E0)
    with pytest.raises(NegativeResponseError) as exc:
        uds.read_data_by_identifier(0x1234)
    assert exc.value.nrc == 0x31
    assert "requestOutOfRange" in str(exc.value)


def test_no_response(transport):
    with pytest.raises(NoResponseError):
        UDSClient(transport, 0x701).tester_present()


def test_read_and_clear_dtcs(transport):
    uds = UDSClient(transport, 0x760)
    [d] = uds.read_dtcs()
    assert d.display == "C0035-1F"
    assert "confirmed" in d.status_flags()
    uds.clear_dtcs()
    assert uds.read_dtcs() == []


def test_status_mask_filters(transport):
    uds = UDSClient(transport, 0x7E0)
    assert [d.code for d in uds.read_dtcs(0x08)] == ["P0301", "P0420"]
    assert [d.code for d in uds.read_dtcs(0x04)] == ["P0171"]


def test_security_access(transport):
    uds = UDSClient(transport, 0x726)
    with pytest.raises(NegativeResponseError) as exc:
        uds.security_access(1, demo_xor)
    assert exc.value.nrc == 0x7F  # not in the default session
    uds.diagnostic_session_control(EXTENDED_SESSION)
    with pytest.raises(NegativeResponseError) as exc:
        uds.security_access(1, lambda seed, level: b"\x00\x00\x00\x00")
    assert exc.value.nrc == 0x35
    uds.security_access(1, demo_xor)
    uds.security_access(1, demo_xor)  # zero seed = already unlocked
    assert uds.read_data_by_identifier(0xF186) == b"\x03"


def test_response_pending_is_skipped():
    class Pending(Transport):
        def send(self, tx_id, payload, rx_id=None):
            return [Message(0x7E8, b"\x7F\x22\x78"), Message(0x7E8, b"\x62\xF1\x90ABC")]

    assert UDSClient(Pending(), 0x7E0).read_data_by_identifier(0xF190) == b"ABC"
