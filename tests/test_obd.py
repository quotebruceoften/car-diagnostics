from cardiag.obd import OBDClient


def test_vin(transport):
    assert OBDClient(transport).vin() == "WVWZZZ1KZ8W123456"


def test_supported_pids_multiple_ecus(transport):
    supported = OBDClient(transport).supported_pids()
    assert set(supported) == {0x7E8, 0x7E9}
    assert {0x0C, 0x0D, 0x42, 0x5C} <= supported[0x7E8]  # spans 3 ranges
    assert 0x20 not in supported[0x7E8]
    assert 0x0C not in supported[0x7E9]


def test_read_live_values(transport):
    obd = OBDClient(transport)
    rpm = obd.read("rpm")
    assert 800 <= rpm.value <= 2600
    assert rpm.ecu == 0x7E8
    assert str(obd.read("baro_pressure")) == "101 kPa"
    status = obd.read("monitor_status").value
    assert status["mil_on"] and status["dtc_count"] == 2


def test_read_dtcs_by_kind(transport):
    obd = OBDClient(transport)
    stored = obd.read_dtcs("stored")
    assert [d.code for d in stored[0x7E8]] == ["P0301", "P0420"]
    assert stored[0x7E9] == []
    pending = obd.read_dtcs("pending")
    assert [d.code for d in pending[0x7E9]] == ["P0730"]
    assert [d.code for d in obd.read_dtcs("permanent")[0x7E8]] == ["P0420"]


def test_freeze_frame_and_clear(transport):
    obd = OBDClient(transport)
    ff = obd.freeze_frame()
    assert ff["dtc"] == "P0301"
    assert "rpm" in ff
    assert obd.clear_dtcs() == [0x7E8, 0x7E9]
    assert obd.read_dtcs("stored")[0x7E8] == []
    assert [d.code for d in obd.read_dtcs("permanent")[0x7E8]] == ["P0420"]  # survive a clear
    assert obd.freeze_frame() == {}
    assert obd.read("monitor_status").value["mil_on"] is False


def test_calibration_ids(transport):
    assert OBDClient(transport).calibration_ids()[0x7E8] == "SC800H6300000000"
