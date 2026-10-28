class CarDiagError(Exception):
    """Base class for all cardiag errors."""


class TransportError(CarDiagError):
    """The adapter or bus failed (no adapter, CAN error, timeout...)."""


class NoResponseError(CarDiagError):
    """No ECU answered a request."""


class ProtocolError(CarDiagError):
    """An ECU answered with something we could not interpret."""


class CodingError(CarDiagError):
    """A coding profile or coding operation is invalid."""
