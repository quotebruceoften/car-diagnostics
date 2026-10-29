import 'dart:async';

import 'package:flutter/foundation.dart';

import '../brands/brand.dart';
import '../brands/scanner.dart';
import '../core/transport/transport.dart';

/// Results of the module scan, shared by the Modules and Coding tabs.
class ScanState extends ChangeNotifier {
  final List<ModuleInfo> results = [];
  bool scanning = false;
  Object? error;
  DateTime? finishedAt;
  int total = 0;
  StreamSubscription<ModuleInfo>? _sub;

  bool get hasResults => results.isNotEmpty;
  List<ModuleInfo> get present => results.where((r) => r.present).toList();
  List<ModuleInfo> get absent => results.where((r) => !r.present).toList();
  List<ModuleInfo> get codable => present.where((r) => r.codable).toList();
  int get faultCount => present.fold(0, (n, r) => n + (r.dtcs?.length ?? 0));

  void start(Transport transport, Brand brand) {
    _sub?.cancel();
    results.clear();
    error = null;
    scanning = true;
    total = brand.modules.length;
    notifyListeners();
    _sub = ModuleScanner(transport, brand).scan().listen(
      (info) {
        results.add(info);
        notifyListeners();
      },
      onError: (Object e) {
        error = e;
        scanning = false;
        notifyListeners();
      },
      onDone: () {
        scanning = false;
        finishedAt = DateTime.now();
        notifyListeners();
      },
    );
  }

  /// Re-reads one module (after clearing faults or changing coding).
  Future<void> refresh(Transport transport, Brand brand, ModuleDef def) async {
    final updated = await ModuleScanner(transport, brand).probe(def);
    final i = results.indexWhere((r) => r.def.txId == def.txId);
    if (i >= 0) {
      results[i] = updated;
      notifyListeners();
    }
  }

  ModuleInfo? find(int txId) {
    for (final r in results) {
      if (r.def.txId == txId) return r;
    }
    return null;
  }

  void reset() {
    _sub?.cancel();
    _sub = null;
    results.clear();
    scanning = false;
    error = null;
    finishedAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
