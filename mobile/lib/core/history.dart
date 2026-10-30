import 'dart:convert';
import 'dart:io';

/// One fault code as saved in a scan record.
class FaultRecord {
  const FaultRecord({required this.code, required this.display, required this.description, this.active});

  final String code;

  /// Code with failure type, e.g. "C0035-1F".
  final String display;
  final String description;
  final bool? active;

  Map<String, dynamic> toJson() => {'code': code, 'display': display, 'description': description, 'active': active};

  factory FaultRecord.fromJson(Map<String, dynamic> j) => FaultRecord(
    code: j['code'] as String,
    display: (j['display'] ?? j['code']) as String,
    description: (j['description'] ?? '') as String,
    active: j['active'] as bool?,
  );
}

class ModuleRecord {
  const ModuleRecord({
    required this.address,
    required this.name,
    this.partNumber = '',
    required this.faults,
    this.faultsReadable = true,
  });

  final String address;
  final String name;
  final String partNumber;
  final List<FaultRecord> faults;
  final bool faultsReadable;

  String get label => address.isEmpty ? name : '$address · $name';

  Map<String, dynamic> toJson() => {
    'address': address,
    'name': name,
    'partNumber': partNumber,
    'faultsReadable': faultsReadable,
    'faults': [for (final f in faults) f.toJson()],
  };

  factory ModuleRecord.fromJson(Map<String, dynamic> j) => ModuleRecord(
    address: (j['address'] ?? '') as String,
    name: j['name'] as String,
    partNumber: (j['partNumber'] ?? '') as String,
    faultsReadable: (j['faultsReadable'] ?? true) as bool,
    faults: [for (final f in (j['faults'] as List? ?? const [])) FaultRecord.fromJson(f as Map<String, dynamic>)],
  );
}

/// The result of one full module scan.
class ScanRecord {
  const ScanRecord({required this.timestamp, required this.vin, required this.carName, required this.modules});

  final DateTime timestamp;
  final String vin;
  final String carName;

  /// Modules that answered.
  final List<ModuleRecord> modules;

  int get faultCount => modules.fold(0, (n, m) => n + m.faults.length);

  /// "module address|code" keys, for comparing scans.
  Set<String> get faultKeys => {
    for (final m in modules)
      for (final f in m.faults) '${m.address}|${m.name}|${f.display}',
  };

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'vin': vin,
    'carName': carName,
    'modules': [for (final m in modules) m.toJson()],
  };

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
    timestamp: DateTime.parse(j['timestamp'] as String),
    vin: (j['vin'] ?? '') as String,
    carName: (j['carName'] ?? '') as String,
    modules: [for (final m in (j['modules'] as List? ?? const [])) ModuleRecord.fromJson(m as Map<String, dynamic>)],
  );
}

/// What changed between two scans of the same car.
class ScanComparison {
  ScanComparison(ScanRecord current, ScanRecord previous)
    : added = _entries(current, current.faultKeys.difference(previous.faultKeys)),
      fixed = _entries(previous, previous.faultKeys.difference(current.faultKeys));

  /// Faults present now that weren't before: (module label, fault).
  final List<(String, FaultRecord)> added;

  /// Faults that were there before and are gone now.
  final List<(String, FaultRecord)> fixed;

  static List<(String, FaultRecord)> _entries(ScanRecord r, Set<String> keys) => [
    for (final m in r.modules)
      for (final f in m.faults)
        if (keys.contains('${m.address}|${m.name}|${f.display}')) (m.label, f),
  ];
}

abstract class HistoryStore {
  Future<void> save(ScanRecord record);

  /// Records for the car with [vin], newest first.
  Future<List<ScanRecord>> list(String vin);
  Future<void> delete(ScanRecord record);
}

class MemoryHistoryStore implements HistoryStore {
  final records = <ScanRecord>[];

  @override
  Future<void> save(ScanRecord record) async => records.add(record);

  @override
  Future<List<ScanRecord>> list(String vin) async =>
      records.where((r) => r.vin == vin).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  @override
  Future<void> delete(ScanRecord record) async => records.remove(record);
}

/// Saves scan records as JSON files, one folder per car.
class FileHistoryStore implements HistoryStore {
  FileHistoryStore(this.directory);
  final Directory directory;

  Directory _carDir(String vin) => Directory('${directory.path}/${vin.isEmpty ? 'unknown' : vin}');

  @override
  Future<void> save(ScanRecord record) async {
    final dir = _carDir(record.vin);
    await dir.create(recursive: true);
    final name = record.timestamp.toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    await File('${dir.path}/$name.json').writeAsString(jsonEncode(record.toJson()));
  }

  @override
  Future<List<ScanRecord>> list(String vin) async {
    final dir = _carDir(vin);
    if (!await dir.exists()) return [];
    final out = <ScanRecord>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(ScanRecord.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        continue; // skip unreadable files
      }
    }
    return out..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<void> delete(ScanRecord record) async {
    final name = record.timestamp.toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final f = File('${_carDir(record.vin).path}/$name.json');
    if (await f.exists()) await f.delete();
  }
}
