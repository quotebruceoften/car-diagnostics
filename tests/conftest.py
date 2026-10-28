import pytest

from cardiag.sim import ELM327Emulator, Vehicle
from cardiag.transport.elm327 import ELM327Transport
from cardiag.transport.simulator import SimulatorTransport


@pytest.fixture(autouse=True)
def cardiag_home(tmp_path, monkeypatch):
    monkeypatch.setenv("CARDIAG_HOME", str(tmp_path / "home"))
    return tmp_path / "home"


@pytest.fixture
def vehicle():
    return Vehicle.demo()


@pytest.fixture(params=["simulator", "elm327"])
def transport(request, vehicle):
    """Every client test runs both directly and through the emulated adapter."""
    if request.param == "simulator":
        return SimulatorTransport(vehicle)
    return ELM327Transport(ELM327Emulator(vehicle))
