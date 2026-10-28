/// Base class for every diagnostics error the app reports to the user.
class CarDiagException implements Exception {
  CarDiagException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The adapter or bus failed (disconnected, CAN error, timeout...).
class TransportException extends CarDiagException {
  TransportException(super.message);
}

/// No ECU answered a request.
class NoResponseException extends CarDiagException {
  NoResponseException(super.message);
}

/// An ECU answered with something we could not interpret.
class ProtocolException extends CarDiagException {
  ProtocolException(super.message);
}

/// A coding profile or coding operation is invalid.
class CodingException extends CarDiagException {
  CodingException(super.message);
}
