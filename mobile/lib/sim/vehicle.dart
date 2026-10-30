/// A virtual car with OBD-II and UDS modules, for the in-app demo mode and tests.
library;

import 'dart:math';
import 'dart:typed_data';

import '../core/coding/security.dart';
import '../core/hex.dart';
import '../core/obd/dtc.dart';
import '../core/transport/transport.dart';

typedef LiveValue = List<int> Function(double t);

class VirtualEcu {
  VirtualEcu(
    this.name,
    this.txId,
    this.rxId, {
    Map<int, List<int>> dids = const {},
    Set<int> writableDids = const {},
    Set<int> securedDids = const {},
    Set<int> lockedDids = const {},
    List<(String, int, int)> udsDtcs = const [],
  }) : dids = {for (final e in dids.entries) e.key: Uint8List.fromList(e.value)},
       writableDids = {...writableDids},
       securedDids = {...securedDids},
       lockedDids = {...lockedDids},
       udsDtcs = [...udsDtcs];

  final String name;
  final int txId;
  final int rxId;
  final Map<int, Uint8List> dids;

  /// Writable in the extended session.
  final Set<int> writableDids;

  /// Writable in the extended session after security access (demo_xor, level 3).
  final Set<int> securedDids;

  /// Never writable (simulates SFD-protected modules).
  final Set<int> lockedDids;

  /// (code, failure type, status)
  final List<(String, int, int)> udsDtcs;

  bool get obd => false;
  int session = 0x01;
  bool unlocked = false;
  Uint8List? _seed;
  int _failedKeys = 0;
  final _random = Random();

  Uint8List? handle(Uint8List p) {
    final sid = p[0];
    if (sid < 0x10) return handleObd(p);
    return switch (sid) {
      0x10 => _session(p),
      0x11 => _reset(p),
      0x14 => _clear(p),
      0x19 => _readDtcs(p),
      0x22 => _readDid(p),
      0x27 => _security(p),
      0x2E => _writeDid(p),
      0x3E => p.length > 1 && p[1] & 0x80 != 0 ? null : _b([0x7E, 0x00]),
      _ => _nrc(sid, 0x11),
    };
  }

  Uint8List? handleObd(Uint8List p) => null;

  void clearObd() {}

  static Uint8List _b(List<int> v) => Uint8List.fromList(v);
  static Uint8List _nrc(int sid, int code) => _b([0x7F, sid, code]);

  Uint8List _session(Uint8List p) {
    if (p.length != 2) return _nrc(0x10, 0x13);
    if (![1, 2, 3].contains(p[1])) return _nrc(0x10, 0x12);
    if (p[1] != session) unlocked = false;
    session = p[1];
    return _b([0x50, p[1], 0x00, 0x32, 0x01, 0xF4]);
  }

  Uint8List _reset(Uint8List p) {
    session = 1;
    unlocked = false;
    return _b([0x51, p.length > 1 ? p[1] : 1]);
  }

  Uint8List _readDid(Uint8List p) {
    if (p.length != 3) return _nrc(0x22, 0x13);
    final did = (p[1] << 8) | p[2];
    if (did == 0xF186) return _b([0x62, p[1], p[2], session]);
    final value = dids[did];
    if (value == null) return _nrc(0x22, 0x31);
    return _b([0x62, p[1], p[2], ...value]);
  }

  Uint8List _writeDid(Uint8List p) {
    if (p.length < 4) return _nrc(0x2E, 0x13);
    final did = (p[1] << 8) | p[2];
    if (lockedDids.contains(did)) return session == 3 ? _nrc(0x2E, 0x33) : _nrc(0x2E, 0x7F);
    if (!writableDids.contains(did) && !securedDids.contains(did)) return _nrc(0x2E, 0x31);
    if (session != 3) return _nrc(0x2E, 0x7F);
    if (securedDids.contains(did) && !unlocked) return _nrc(0x2E, 0x33);
    if (p.length - 3 != dids[did]!.length) return _nrc(0x2E, 0x13);
    dids[did] = Uint8List.fromList(p.sublist(3));
    return _b([0x6E, p[1], p[2]]);
  }

  Uint8List _security(Uint8List p) {
    if (p.length < 2) return _nrc(0x27, 0x13);
    if (session == 1) return _nrc(0x27, 0x7F);
    final level = p[1];
    if (level.isOdd) {
      if (_failedKeys >= 3) return _nrc(0x27, 0x36);
      if (unlocked) return _b([0x67, level, 0, 0, 0, 0]);
      _seed = Uint8List.fromList(List.generate(4, (_) => 1 + _random.nextInt(255)));
      return _b([0x67, level, ..._seed!]);
    }
    final seed = _seed;
    _seed = null;
    if (seed == null) return _nrc(0x27, 0x24);
    if (!bytesEqual(p.sublist(2), demoXor(seed, level - 1))) {
      _failedKeys++;
      return _nrc(0x27, 0x35);
    }
    unlocked = true;
    _failedKeys = 0;
    return _b([0x67, level]);
  }

  Uint8List _readDtcs(Uint8List p) {
    if (p.length < 3 || p[1] != 0x02) return _nrc(0x19, 0x12);
    return _b([
      0x59,
      0x02,
      0xFF,
      for (final (code, ftb, status) in udsDtcs)
        if (status & p[2] != 0) ...[...encodeDtc(code), ftb, status],
    ]);
  }

  Uint8List _clear(Uint8List p) {
    if (p.length != 4) return _nrc(0x14, 0x13);
    // Faults that are still present come straight back, like in a real car.
    udsDtcs.removeWhere((d) => d.$3 & 0x01 == 0);
    clearObd();
    return _b([0x54]);
  }
}

/// An emissions-relevant module that also answers SAE J1979 requests.
class ObdEcu extends VirtualEcu {
  ObdEcu(
    super.name,
    super.txId,
    super.rxId, {
    super.dids,
    super.udsDtcs,
    this.vin = '',
    List<String> stored = const [],
    List<String> pending = const [],
    List<String> permanent = const [],
    this.live = const {},
  }) : stored = [...stored],
       pending = [...pending],
       permanent = [...permanent] {
    if (this.stored.isNotEmpty) {
      freeze = {for (final e in live.entries) e.key: e.value(12.5), 0x02: encodeDtc(this.stored.first)};
    }
  }

  final String vin;
  final List<String> stored;
  final List<String> pending;
  final List<String> permanent;
  final Map<int, LiveValue> live;
  Map<int, List<int>> freeze = {};
  int distanceSinceClear = 1234;

  /// Clearing codes resets the emissions self-tests until the car is driven.
  bool monitorsIncomplete = false;
  final _start = DateTime.now();

  @override
  bool get obd => true;

  double get _t => DateTime.now().difference(_start).inMilliseconds / 1000;

  @override
  void clearObd() {
    stored.clear();
    pending.clear();
    freeze = {};
    distanceSinceClear = 0;
    monitorsIncomplete = true;
  }

  Set<int> get _supported => {...live.keys, 0x01, 0x31};

  List<int>? _pid(int pid) {
    if (pid % 0x20 == 0) {
      // "PIDs supported" bitmap; the last bit says the next range exists.
      final s = _supported;
      if (pid > 0 && !s.any((p) => p > pid)) return null;
      var bits = 0;
      for (var i = 0; i < 32; i++) {
        final n = pid + i + 1;
        if (s.contains(n) || (i == 31 && s.any((p) => p > n))) bits |= 1 << (31 - i);
      }
      return [(bits >> 24) & 0xFF, (bits >> 16) & 0xFF, (bits >> 8) & 0xFF, bits & 0xFF];
    }
    if (pid == 0x01) {
      // Petrol engine; catalyst, EVAP, O2 sensor and heater monitors supported.
      final incomplete = monitorsIncomplete ? 0x25 : 0x00;
      return [(stored.isNotEmpty ? 0x80 : 0) | stored.length, 0x07, 0x65, incomplete];
    }
    if (pid == 0x31) return [distanceSinceClear >> 8, distanceSinceClear & 0xFF];
    return live[pid]?.call(_t);
  }

  @override
  Uint8List? handleObd(Uint8List p) {
    final mode = p[0];
    if (mode == 0x01 && p.length >= 2) {
      final out = [0x41];
      for (final pid in p.sublist(1, min(p.length, 7))) {
        final d = _pid(pid);
        if (d != null) out.addAll([pid, ...d]);
      }
      return out.length > 1 ? Uint8List.fromList(out) : null;
    }
    if (mode == 0x02 && p.length >= 3) {
      if (p[1] == 0x02) {
        return Uint8List.fromList([
          0x42,
          0x02,
          p[2],
          ...(freeze[0x02] ?? [0, 0]),
        ]);
      }
      final d = freeze[p[1]];
      return d == null ? null : Uint8List.fromList([0x42, p[1], p[2], ...d]);
    }
    if (mode == 0x03 || mode == 0x07 || mode == 0x0A) {
      final codes = mode == 0x03 ? stored : (mode == 0x07 ? pending : permanent);
      return Uint8List.fromList([mode + 0x40, codes.length, for (final c in codes) ...encodeDtc(c)]);
    }
    if (mode == 0x04) {
      clearObd();
      return Uint8List.fromList([0x44]);
    }
    if (mode == 0x09 && p.length >= 2 && p[1] == 0x02 && vin.isNotEmpty) {
      return Uint8List.fromList([0x49, 0x02, 0x01, ...vin.codeUnits]);
    }
    return null;
  }
}

List<int> _u16(num v) => [(v.toInt() >> 8) & 0xFF, v.toInt() & 0xFF];

Map<int, LiveValue> _engineLive() {
  double wave(double t) => (1 + sin(t / 3)) / 2;
  return {
    0x04: (t) => [(255 * (0.2 + 0.4 * wave(t))).toInt()],
    0x05: (t) => [40 + min(90, (20 + t * 2).toInt())],
    0x06: (t) => [128 + (6 * sin(t)).toInt()],
    0x07: (t) => [131],
    0x0B: (t) => [(30 + 60 * wave(t)).toInt()],
    0x0C: (t) => _u16((800 + 1800 * wave(t)) * 4),
    0x0D: (t) => [(60 * (1 + sin(t / 3 - 0.6)) / 2).toInt()],
    0x0E: (t) => [((12 + 8 * sin(t / 3) + 64) * 2).toInt()],
    0x0F: (t) => [40 + 24],
    0x10: (t) => _u16(100 * (3 + 20 * wave(t))),
    0x11: (t) => [(255 * (0.12 + 0.5 * wave(t))).toInt()],
    0x1F: (t) => _u16(t),
    0x2F: (t) => [(255 * 0.62).toInt()],
    0x33: (t) => [101],
    0x42: (t) => _u16(14100 + 150 * sin(t)),
    0x46: (t) => [40 + 18],
    0x5C: (t) => [40 + min(100, (15 + t * 1.5).toInt())],
  };
}

class Vehicle {
  Vehicle(this.name, this.vin, this.ecus);

  final String name;
  final String vin;
  final List<VirtualEcu> ecus;

  VirtualEcu? ecu(int txId) {
    for (final e in ecus) {
      if (e.txId == txId) return e;
    }
    return null;
  }

  /// Delivers a request; returns [(response CAN id, payload)].
  List<(int, Uint8List)> handle(int txId, List<int> payload) {
    if (payload.isEmpty) return const [];
    final p = Uint8List.fromList(payload);
    final targets = txId == obdBroadcastId ? ecus.where((e) => e.obd) : [?ecu(txId)];
    return [
      for (final e in targets)
        if (e.handle(p) case final reply?) (e.rxId, reply),
    ];
  }

  /// A 2017 VW Golf with modules at VW Group addresses.
  factory Vehicle.demoGolf() {
    const vin = 'WVWZZZAUZHW123456';
    final vinBytes = vin.codeUnits;
    List<int> ascii(String s) => s.codeUnits;
    return Vehicle('Demo VW Golf (simulated)', vin, [
      ObdEcu(
        'Engine',
        0x7E0,
        0x7E8,
        vin: vin,
        stored: ['P0301', 'P0420'],
        pending: ['P0171'],
        permanent: ['P0420'],
        live: _engineLive(),
        dids: {
          0xF187: ascii('04E906016DE'),
          0xF189: ascii('0004'),
          0xF191: ascii('04E907309C'),
          0xF197: ascii('R4 1.4l TFSI'),
          0xF18C: ascii('VWX7Z0000123456'),
          0xF190: vinBytes,
        },
        udsDtcs: [('P0301', 0x00, 0x2B), ('P0420', 0x00, 0x28), ('P0171', 0x00, 0x24)],
      ),
      ObdEcu(
        'Transmission',
        0x7E1,
        0x7E9,
        pending: ['P0730'],
        live: {
          0x0D: _engineLive()[0x0D]!,
          0x46: (t) => [58],
        },
        dids: {0xF187: ascii('0CW300040H'), 0xF189: ascii('3110'), 0xF197: ascii('DQ200-MQB'), 0xF190: vinBytes},
        udsDtcs: [('P0730', 0x00, 0x24)],
      ),
      VirtualEcu(
        'Brakes',
        0x713,
        0x77D,
        dids: {0xF187: ascii('5Q0907379Q'), 0xF189: ascii('0490'), 0xF197: ascii('ESC'), 0xF190: vinBytes},
        udsDtcs: [('C0035', 0x1F, 0x28)],
      ),
      VirtualEcu(
        'Central electrics',
        0x70E,
        0x778,
        dids: {
          0xF187: ascii('5Q0937DEMO'),
          0xF189: ascii('0254'),
          0xF197: ascii('BCM MQB'),
          0xF190: vinBytes,
          0x0600: [
            0x15, 0x03, 0x1E, 0x00, 0x02, 0x00, 0x48, 0x10, 0x00, 0x00, //
            0x4F, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, //
            0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          ],
        },
        writableDids: {0x0600},
        udsDtcs: [('U0155', 0x00, 0x08)],
      ),
      VirtualEcu(
        'Airbags',
        0x715,
        0x77F,
        dids: {0xF187: ascii('5Q0959655BJ'), 0xF197: ascii('AirbagVW20'), 0xF190: vinBytes},
      ),
      VirtualEcu(
        'Instrument cluster',
        0x714,
        0x77E,
        dids: {
          0xF187: ascii('5G1920741B'),
          0xF197: ascii('KOMBI'),
          0xF190: vinBytes,
          0x0600: [0x2D, 0x0F, 0x00, 0x10, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        },
        writableDids: {0x0600},
      ),
      VirtualEcu(
        'Gateway',
        0x710,
        0x77A,
        dids: {
          0xF187: ascii('5Q0907530AA'),
          0xF197: ascii('J533 Gateway'),
          0xF190: vinBytes,
          0x0600: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        },
        lockedDids: {0x0600},
      ),
    ]);
  }
}

/// Talks to a [Vehicle] directly, with an optional delay to feel realistic.
class SimulatorTransport implements Transport {
  SimulatorTransport([Vehicle? vehicle, this.latency = Duration.zero]) : vehicle = vehicle ?? Vehicle.demoGolf();

  final Vehicle vehicle;
  final Duration latency;

  @override
  String get description => vehicle.name;

  @override
  Future<List<Message>> send(int txId, List<int> payload, {int? rxId}) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return [
      for (final (id, data) in vehicle.handle(txId, payload))
        if (rxId == null || id == rxId) Message(id, data),
    ];
  }

  @override
  Future<void> close() async {}
}
