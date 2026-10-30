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
  const ScanRecord({
    required this.timestamp,
    required this.vin,
    required this.carName,
    required this.modules,
    this.source = '',
  });

  final DateTime timestamp;
  final String vin;
  final String carName;

  /// Where the scan came from when not this app, e.g. "VCDS".
  final String source;

  /// Modules that answered.
  final List<ModuleRecord> modules;

  int get faultCount => modules.fold(0, (n, m) => n + m.faults.length);

  /// Identifies a fault across scans: module address and code, so scans
  /// from different tools (which name modules differently) line up.
  static String faultKey(ModuleRecord m, FaultRecord f) =>
      '${m.address.isEmpty ? m.name : m.address.toUpperCase()}|${f.code.toUpperCase()}';

  Set<String> get faultKeys => {
    for (final m in modules)
      for (final f in m.faults) faultKey(m, f),
  };

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'vin': vin,
    'carName': carName,
    if (source.isNotEmpty) 'source': source,
    'modules': [for (final m in modules) m.toJson()],
  };

  factory ScanRecord.fromJson(Map<String, dynamic> j) => ScanRecord(
    timestamp: DateTime.parse(j['timestamp'] as String),
    vin: (j['vin'] ?? '') as String,
    carName: (j['carName'] ?? '') as String,
    source: (j['source'] ?? '') as String,
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
        if (keys.contains(ScanRecord.faultKey(m, f))) (m.label, f),
  ];
}

/// How one fault has behaved over the saved scans of a car.
class FaultTrend {
  FaultTrend(this.moduleLabel, this.fault, this.first);

  final String moduleLabel;

  /// The fault as last seen.
  FaultRecord fault;

  /// Scans that contain it, and all scans since it first appeared.
  int seen = 0;
  int since = 0;
  DateTime first;
  late DateTime last = first;

  /// In the newest scan.
  bool current = false;

  /// The first scan after [last] that no longer had it.
  DateTime? goneSince;

  bool get recurring => seen >= 2;
}

/// Fault history over every saved scan of one car.
class FaultTrends {
  /// [records] in any order.
  FaultTrends(List<ScanRecord> records) : scans = records.length {
    final sorted = [...records]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (final (i, r) in sorted.indexed) {
      final keys = r.faultKeys;
      for (final m in r.modules) {
        for (final f in m.faults) {
          final key = ScanRecord.faultKey(m, f);
          final t = _byKey.putIfAbsent(key, () => FaultTrend(m.label, f, r.timestamp)..since = sorted.length - i);
          if (t.seen == 0 || !t.last.isAtSameMomentAs(r.timestamp)) t.seen++;
          t
            ..last = r.timestamp
            ..fault = f
            ..goneSince = null;
        }
      }
      for (final t in _byKey.entries) {
        if (!keys.contains(t.key) && t.value.goneSince == null && t.value.last.isBefore(r.timestamp)) {
          t.value.goneSince = r.timestamp;
        }
      }
    }
    if (sorted.isNotEmpty) {
      for (final key in sorted.last.faultKeys) {
        _byKey[key]?.current = true;
      }
    }
  }

  final int scans;
  final _byKey = <String, FaultTrend>{};

  FaultTrend? of(ModuleRecord m, FaultRecord f) => _byKey[ScanRecord.faultKey(m, f)];

  /// Lookup for live scan results, by module address (or name) and code.
  FaultTrend? find(String address, String name, String code) =>
      _byKey['${address.isEmpty ? name : address.toUpperCase()}|${code.toUpperCase()}'];

  /// Current faults first (most often seen first), then gone ones.
  List<FaultTrend> get all => _byKey.values.toList()
    ..sort((a, b) {
      if (a.current != b.current) return a.current ? -1 : 1;
      final c = b.seen.compareTo(a.seen);
      return c != 0 ? c : b.last.compareTo(a.last);
    });
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
