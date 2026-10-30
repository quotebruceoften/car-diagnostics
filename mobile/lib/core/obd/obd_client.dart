import 'dart:typed_data';

import '../errors.dart';
import '../hex.dart';
import '../transport/transport.dart';
import 'dtc.dart';
import 'pids.dart';
import 'readiness.dart';

const obdEcuNames = {0x7E8: 'Engine', 0x7E9: 'Transmission', 0x7EA: 'ECU #3', 0x7EB: 'ECU #4', 0x7EC: 'Hybrid / EV'};

String obdEcuName(int rxId) => obdEcuNames[rxId] ?? 'ECU ${hexId(rxId)}';

class Reading {
  const Reading(this.pid, this.value, this.ecu);
  final Pid pid;
  final Object value;
  final int ecu;

  double? get numeric => value is num ? (value as num).toDouble() : null;

  @override
  String toString() => pid.unit.isEmpty ? '$value' : '$value ${pid.unit}';
}

enum DtcKind { stored, pending, permanent }

/// OBD-II (SAE J1979) client. Works on every car sold since ~2008.
class ObdClient {
  ObdClient(this.transport, {this.txId = obdBroadcastId});

  final Transport transport;
  final int txId;

  /// Returns {ecu rx id: data after the echoed mode (and PID) bytes}.
  Future<Map<int, Uint8List>> query(int mode, [List<int> params = const []]) async {
    final positive = mode + 0x40;
    final echo = (mode == 0x03 || mode == 0x04 || mode == 0x07 || mode == 0x0A) ? 1 : 1 + params.length;
    final results = <int, Uint8List>{};
    for (final msg in await transport.send(txId, [mode, ...params])) {
      if (msg.data.isEmpty || msg.data[0] == 0x7F) continue;
      if (msg.data[0] != positive) {
        throw ProtocolException('Unexpected reply ${bytesToHex(msg.data)} to mode $mode');
      }
      results[msg.rxId] = Uint8List.sublistView(msg.data, echo);
    }
    return results;
  }

  (int, Uint8List) _first(Map<int, Uint8List> results, String what) {
    if (results.isEmpty) throw NoResponseException('No ECU answered $what');
    final ecu = results.keys.reduce((a, b) => a < b ? a : b);
    return (ecu, results[ecu]!);
  }

  /// {ecu: supported mode 01 PIDs}
  Future<Map<int, Set<int>>> supportedPids() async {
    final supported = <int, Set<int>>{};
    Set<int>? pending;
    for (var base = 0; base <= 0xE0; base += 0x20) {
      var results = await query(0x01, [base]);
      if (pending != null) {
        results = {
          for (final e in results.entries)
            if (pending.contains(e.key)) e.key: e.value,
        };
      }
      if (results.isEmpty) break;
      for (final e in results.entries) {
        if (e.value.length >= 4) supported.putIfAbsent(e.key, () => {}).addAll(decodeSupported(base, e.value));
      }
      pending = {
        for (final e in supported.entries)
          if (e.value.contains(base + 0x20)) e.key,
      };
      if (pending.isEmpty) break;
    }
    for (final s in supported.values) {
      s.removeAll([0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0]);
    }
    return supported;
  }

  Future<Reading> read(Object pid) async {
    final p = lookupPid(pid);
    final (ecu, data) = _first(await query(0x01, [p.pid]), p.description);
    if (data.length < p.length) throw ProtocolException('Short reply for ${p.name}');
    return Reading(p, p.decode(data.sublist(0, p.length)), ecu);
  }

  Future<MonitorStatus> monitorStatus() async => (await read(0x01)).value as MonitorStatus;

  /// Emissions readiness monitors, from the engine computer.
  Future<Readiness> readiness() async {
    final (_, data) = _first(await query(0x01, [0x01]), 'the readiness request');
    if (data.length < 4) throw ProtocolException('Short readiness reply');
    return decodeReadiness(data);
  }

  Future<Map<int, List<Dtc>>> readDtcs([DtcKind kind = DtcKind.stored]) async {
    final mode = switch (kind) {
      DtcKind.stored => 0x03,
      DtcKind.pending => 0x07,
      DtcKind.permanent => 0x0A,
    };
    return {for (final e in (await query(mode)).entries) e.key: parseObdDtcs(e.value)};
  }

  /// Mode 04: clears DTCs and freeze frames, resets readiness monitors.
  Future<List<int>> clearDtcs() async => (await query(0x04)).keys.toList()..sort();

  /// The stored freeze frame: the DTC that triggered it plus every PID it holds.
  Future<(String, List<Reading>)?> freezeFrame() async {
    final (ecu, data) = _first(await query(0x02, [0x02, 0x00]), 'the freeze frame request');
    if (data.length < 2 || (data[0] == 0 && data[1] == 0)) return null;
    final readings = <Reading>[];
    for (final p in allPids.where((p) => p.pid != 0x01)) {
      final reply = (await query(0x02, [p.pid, 0x00]))[ecu];
      if (reply != null && reply.length >= p.length) readings.add(Reading(p, p.decode(reply), ecu));
    }
    return (decodeDtc(data), readings);
  }

  Future<String> vin() async {
    final (_, data) = _first(await query(0x09, [0x02]), 'the VIN request');
    // CAN replies start with a 1-byte item count.
    final raw = data.length == 18 ? data.sublist(1) : data;
    return String.fromCharCodes(raw.where((b) => b >= 0x20 && b < 0x7F)).trim();
  }
}
