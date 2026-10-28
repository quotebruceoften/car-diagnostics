import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../errors.dart';
import '../hex.dart';
import '../uds/uds_client.dart';
import 'security.dart';

/// A saved copy of a module's coding, taken before every write.
class CodingBackup {
  CodingBackup({
    required this.moduleName,
    required this.txId,
    required this.did,
    required this.data,
    required this.timestamp,
    this.vin = '',
    this.partNumber = '',
    this.profileId,
  });

  final String moduleName;
  final int txId;
  final int did;
  final Uint8List data;
  final DateTime timestamp;
  final String vin;
  final String partNumber;
  final String? profileId;

  Map<String, dynamic> toJson() => {
    'module': moduleName,
    'tx_id': hexId(txId),
    'did': hexId(did, 4),
    'data': bytesToHex(data),
    'timestamp': timestamp.toUtc().toIso8601String(),
    'vin': vin,
    'part_number': partNumber,
    if (profileId != null) 'profile': profileId,
  };

  factory CodingBackup.fromJson(Map<String, dynamic> j) => CodingBackup(
    moduleName: j['module'] as String,
    txId: int.parse((j['tx_id'] as String).substring(2), radix: 16),
    did: int.parse((j['did'] as String).substring(2), radix: 16),
    data: hexToBytes(j['data'] as String),
    timestamp: DateTime.parse(j['timestamp'] as String),
    vin: (j['vin'] ?? '') as String,
    partNumber: (j['part_number'] ?? '') as String,
    profileId: j['profile'] as String?,
  );
}

abstract class BackupStore {
  Future<void> save(CodingBackup backup);
  Future<List<CodingBackup>> list({int? txId, String? vin});
}

class MemoryBackupStore implements BackupStore {
  final backups = <CodingBackup>[];

  @override
  Future<void> save(CodingBackup backup) async => backups.add(backup);

  @override
  Future<List<CodingBackup>> list({int? txId, String? vin}) async => [
    for (final b in backups.reversed)
      if ((txId == null || b.txId == txId) && (vin == null || b.vin == vin)) b,
  ];
}

/// Stores each backup as a JSON file in [directory].
class FileBackupStore implements BackupStore {
  FileBackupStore(this.directory);
  final Directory directory;

  @override
  Future<void> save(CodingBackup backup) async {
    await directory.create(recursive: true);
    final stamp = backup.timestamp.toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final file = File('${directory.path}/${backup.txId.toRadixString(16)}-$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(backup.toJson()));
  }

  @override
  Future<List<CodingBackup>> list({int? txId, String? vin}) async {
    if (!await directory.exists()) return [];
    final out = <CodingBackup>[];
    await for (final f in directory.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final b = CodingBackup.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        if ((txId == null || b.txId == txId) && (vin == null || b.vin == vin)) out.add(b);
      } catch (_) {
        continue; // ignore unreadable files
      }
    }
    return out..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }
}

/// How to get write access to a module's coding.
class CodingAccess {
  const CodingAccess({this.session = extendedSession, this.securityLevel, this.securityAlgorithm});
  final int session;
  final int? securityLevel;
  final String? securityAlgorithm;
}

/// Reads and writes one module's coding block: backup first, write, then
/// read back to verify.
class Coder {
  Coder(
    this.uds, {
    required this.did,
    required this.store,
    required this.moduleName,
    this.access = const CodingAccess(),
  });

  final UdsClient uds;
  final int did;
  final BackupStore store;
  final String moduleName;
  final CodingAccess access;

  Future<Uint8List> read() => uds.readDataByIdentifier(did);

  Future<CodingBackup> backup({Uint8List? data, String vin = '', String partNumber = '', String? profileId}) async {
    final b = CodingBackup(
      moduleName: moduleName,
      txId: uds.txId,
      did: did,
      data: data ?? await read(),
      timestamp: DateTime.now(),
      vin: vin,
      partNumber: partNumber,
      profileId: profileId,
    );
    await store.save(b);
    return b;
  }

  /// Backs up the current coding, writes [newData] and verifies it.
  /// Returns the backup of the previous coding.
  Future<CodingBackup> write(Uint8List newData, {String vin = '', String partNumber = '', String? profileId}) async {
    final old = await read();
    if (old.length != newData.length) {
      throw CodingException('New coding is ${newData.length} bytes but the module has ${old.length}');
    }
    final saved = await backup(data: old, vin: vin, partNumber: partNumber, profileId: profileId);
    if (bytesEqual(old, newData)) return saved;
    await uds.diagnosticSessionControl(access.session);
    try {
      if (access.securityLevel != null) {
        final name = access.securityAlgorithm;
        if (name == null) throw CodingException('This module needs security access but no algorithm is set');
        await uds.securityAccess(access.securityLevel!, securityAlgorithm(name));
      }
      await uds.writeDataByIdentifier(did, newData);
      final readback = await read();
      if (!bytesEqual(readback, newData)) {
        throw CodingException(
          'Verification failed: the module reports ${bytesToHex(readback, separator: ' ')} '
          'instead of the new coding. The previous coding was backed up.',
        );
      }
    } finally {
      try {
        await uds.diagnosticSessionControl(defaultSession);
      } on CarDiagException {
        // The session times out by itself anyway.
      }
    }
    return saved;
  }
}
