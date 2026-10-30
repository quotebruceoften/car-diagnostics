import 'dart:typed_data';

import '../hex.dart';

/// Functional (broadcast) request ID for OBD-II on 11-bit CAN.
const obdBroadcastId = 0x7DF;

/// A complete (ISO-TP reassembled) diagnostic message received from an ECU.
class Message {
  const Message(this.rxId, this.data);
  final int rxId;
  final Uint8List data;

  @override
  String toString() => 'Message(${hexId(rxId)}, ${bytesToHex(data, separator: ' ')})';
}

/// Sends a diagnostic payload to a CAN ID and collects the replies.
///
/// Implementations hide adapter details and ISO-TP segmentation.
abstract class Transport {
  /// Sends [payload] to [txId]; returns every reply. [rxId] restricts replies
  /// to one ECU, `null` accepts all (OBD broadcast requests).
  Future<List<Message>> send(int txId, List<int> payload, {int? rxId});

  String get description;

  Future<void> close() async {}
}

/// Transports that can measure the car's battery voltage at the OBD port
/// directly (ELM327 "AT RV"), which works even while the engine cranks.
abstract interface class BatteryVoltageReader {
  Future<double?> batteryVoltage();
}

/// Serialises async operations: adapters can only do one request at a time,
/// but the UI (live data, scans, button presses) fires them concurrently.
class AsyncLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _last.then((_) => action());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }
}
