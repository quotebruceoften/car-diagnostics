import 'dart:typed_data';

import '../errors.dart';
import '../hex.dart';
import '../obd/dtc.dart';
import '../transport/transport.dart';

const nrcNames = {
  0x10: 'general reject',
  0x11: 'service not supported',
  0x12: 'sub-function not supported',
  0x13: 'incorrect message length or format',
  0x14: 'response too long',
  0x21: 'busy, repeat request',
  0x22: 'conditions not correct',
  0x24: 'request sequence error',
  0x25: 'no response from sub-net component',
  0x26: 'failure prevents execution',
  0x31: 'request out of range',
  0x33: 'security access denied',
  0x35: 'invalid key',
  0x36: 'exceeded number of attempts',
  0x37: 'required time delay not expired',
  0x72: 'general programming failure',
  0x78: 'response pending',
  0x7E: 'sub-function not supported in active session',
  0x7F: 'service not supported in active session',
};

/// Standard identification DIDs (ISO 14229-1 annex C).
const standardDids = {
  0xF187: 'Part number',
  0xF189: 'Software version',
  0xF18C: 'Serial number',
  0xF190: 'VIN',
  0xF191: 'Hardware number',
  0xF197: 'System name',
};

const defaultSession = 0x01;
const programmingSession = 0x02;
const extendedSession = 0x03;

typedef KeyFunction = Uint8List Function(Uint8List seed, int level);

class NegativeResponseException extends CarDiagException {
  NegativeResponseException(this.service, this.nrc)
    : super(
        'Module rejected the request: ${nrcNames[nrc] ?? 'unknown reason'} '
        '(service 0x${service.toRadixString(16).toUpperCase()}, NRC 0x${nrc.toRadixString(16).toUpperCase()})',
      );
  final int service;
  final int nrc;
}

/// Unified Diagnostic Services (ISO 14229-1) client for one module.
class UdsClient {
  UdsClient(this.transport, this.txId, {int? rxId}) : rxId = rxId ?? txId + 8;

  final Transport transport;
  final int txId;
  final int rxId;

  /// Sends a request; returns the positive response (including its SID).
  Future<Uint8List> request(List<int> payload) async {
    final sid = payload[0];
    final replies = [
      for (final m in await transport.send(txId, payload, rxId: rxId))
        if (m.rxId == rxId) m.data,
    ];
    // "Response pending" (NRC 0x78) precedes the real answer; drop it.
    final finals = replies.where((r) => !(r.length >= 3 && r[0] == 0x7F && r[2] == 0x78)).toList();
    if (finals.isEmpty) {
      throw NoResponseException(
        replies.isEmpty ? 'No response from module ${hexId(txId)}' : 'Module ${hexId(txId)} is still busy; try again',
      );
    }
    final reply = finals.last;
    if (reply[0] == 0x7F) {
      if (reply.length < 3) throw ProtocolException('Malformed negative response ${bytesToHex(reply)}');
      throw NegativeResponseException(reply[1], reply[2]);
    }
    if (reply[0] != sid + 0x40) {
      throw ProtocolException('Unexpected reply ${bytesToHex(reply)} to service 0x${sid.toRadixString(16)}');
    }
    return reply;
  }

  Future<void> diagnosticSessionControl(int session) => request([0x10, session]);

  Future<void> ecuReset([int type = 0x01]) => request([0x11, type]);

  Future<void> testerPresent() => request([0x3E, 0x00]);

  Future<Uint8List> readDataByIdentifier(int did) async {
    final reply = await request([0x22, did >> 8, did & 0xFF]);
    if (reply.length < 3 || reply[1] != did >> 8 || reply[2] != (did & 0xFF)) {
      throw ProtocolException('Reply for the wrong data identifier: ${bytesToHex(reply)}');
    }
    return Uint8List.sublistView(reply, 3);
  }

  Future<void> writeDataByIdentifier(int did, List<int> data) => request([0x2E, did >> 8, did & 0xFF, ...data]);

  /// Unlocks security [level] (odd) using [keyFunction].
  Future<void> securityAccess(int level, KeyFunction keyFunction) async {
    if (level.isEven) throw ArgumentError('security access level must be odd');
    final seed = Uint8List.sublistView(await request([0x27, level]), 2);
    if (seed.every((b) => b == 0)) return; // already unlocked
    await request([0x27, level + 1, ...keyFunction(seed, level)]);
  }

  /// ReadDTCInformation / reportDTCByStatusMask.
  Future<List<Dtc>> readDtcs([int statusMask = 0xFF]) async {
    final reply = await request([0x19, 0x02, statusMask]);
    return [
      for (var i = 3; i + 3 < reply.length; i += 4)
        Dtc(decodeDtc(reply.sublist(i, i + 2)), failureType: reply[i + 2], status: reply[i + 3]),
    ];
  }

  Future<void> clearDtcs([int group = 0xFFFFFF]) =>
      request([0x14, (group >> 16) & 0xFF, (group >> 8) & 0xFF, group & 0xFF]);

  /// Reads each of [dids] the module supports; unsupported ones are skipped.
  Future<Map<int, Uint8List>> readMany(Iterable<int> dids) async {
    final out = <int, Uint8List>{};
    for (final did in dids) {
      try {
        out[did] = await readDataByIdentifier(did);
      } on NegativeResponseException {
        continue;
      }
    }
    return out;
  }
}
