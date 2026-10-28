import pytest

from cardiag.cli import main


def run(capsys, *argv):
    code = main(["--sim", *argv])
    out = capsys.readouterr()
    return code, out.out, out.err


def test_info(capsys):
    code, out, _ = run(capsys, "info")
    assert code == 0
    assert "WVWZZZ1KZ8W123456" in out and "MIL       : ON" in out


def test_dtc_all(capsys):
    code, out, _ = run(capsys, "dtc", "--all")
    assert code == 0 and "P0301" in out and "P0730" in out


def test_dtc_clear_requires_confirmation(capsys, monkeypatch):
    monkeypatch.setattr("sys.stdin.isatty", lambda: False)
    code, _, err = run(capsys, "dtc", "clear")
    assert code == 1 and "--yes" in err
    assert run(capsys, "dtc", "clear", "--yes")[0] == 0


def test_live_csv(capsys, tmp_path):
    csv_path = tmp_path / "log.csv"
    code, out, _ = run(capsys, "live", "rpm", "speed", "-n", "2", "-i", "0", "--csv", str(csv_path))
    assert code == 0
    lines = csv_path.read_text().splitlines()
    assert lines[0] == "timestamp,rpm (rpm),speed (km/h)"
    assert len(lines) == 3


def test_unknown_pid(capsys):
    code, _, err = run(capsys, "live", "bogus", "-n", "1")
    assert code == 2 and "unknown PID" in err


def test_uds_scan(capsys):
    code, out, _ = run(capsys, "uds", "scan")
    assert code == 0 and "4 module(s) found" in out and "BCM PQ35" in out


def test_uds_commands(capsys):
    assert "06K907425B" in run(capsys, "uds", "info", "--tx", "7E0")[1]
    assert "C0035-1F" in run(capsys, "uds", "dtc", "--tx", "760")[1]
    assert "WVWZZZ1KZ8W123456" in run(capsys, "uds", "read", "--tx", "0x7E0", "F190")[1]
    assert "7F 2E 7F" in run(capsys, "uds", "raw", "--tx", "726", "2E0600", "00")[1]


def test_coding_show_and_set(capsys, cardiag_home):
    code, out, _ = run(capsys, "coding", "show", "demo_bcm")
    assert code == 0 and "15 km/h" in out
    code, out, _ = run(capsys, "coding", "set", "demo_bcm", "drl=off", "--dry-run")
    assert code == 0 and "Dry run" in out and not (cardiag_home / "backups").exists()
    code, out, _ = run(capsys, "coding", "set", "demo_bcm", "drl=off", "region=US", "--yes")
    assert code == 0 and "verified" in out
    assert len(list((cardiag_home / "backups").glob("demo_bcm-*.json"))) == 1


def test_coding_bad_value(capsys):
    code, _, err = run(capsys, "coding", "set", "demo_bcm", "comfort_blinks=9", "--yes")
    assert code == 2 and "outside 1..7" in err


def test_offline_commands(capsys):
    assert main(["pids"]) == 0
    assert main(["coding", "profiles"]) == 0
    assert "demo_bcm" in capsys.readouterr().out
