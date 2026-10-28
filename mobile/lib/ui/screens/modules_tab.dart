import 'dart:async';

import 'package:flutter/material.dart';

import '../../brands/scanner.dart';
import '../session.dart';
import '../widgets/common.dart';
import 'module_screen.dart';

/// Scans the car's modules (control units) and lists their fault codes.
class ModulesTab extends StatefulWidget {
  const ModulesTab({super.key});

  @override
  State<ModulesTab> createState() => _ModulesTabState();
}

class _ModulesTabState extends State<ModulesTab> {
  final _results = <ModuleInfo>[];
  String? _brandId;
  bool _scanning = false;
  Object? _error;
  StreamSubscription<ModuleInfo>? _scan;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brand = SessionScope.of(context).brand;
    if (brand.id != _brandId) {
      // The make changed: earlier results used another module list.
      _scan?.cancel();
      _brandId = brand.id;
      _results.clear();
      _scanning = false;
    }
  }

  @override
  void dispose() {
    _scan?.cancel();
    super.dispose();
  }

  void _startScan() {
    final session = SessionScope.read(context);
    setState(() {
      _results.clear();
      _error = null;
      _scanning = true;
    });
    _scan = ModuleScanner(session.transport, session.brand).scan().listen(
      (info) => setState(() => _results.add(info)),
      onError: (Object e) => setState(() {
        _error = e;
        _scanning = false;
      }),
      onDone: () => setState(() => _scanning = false),
    );
  }

  Future<void> _open(ModuleInfo info) async {
    final session = SessionScope.read(context);
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ModuleScreen(module: info.def)));
    // Fault codes may have been cleared or coding changed; refresh this row.
    if (!mounted || !session.connected) return;
    try {
      final updated = await ModuleScanner(session.transport, session.brand).probe(info.def);
      final i = _results.indexOf(info);
      if (mounted && i >= 0) setState(() => _results[i] = updated);
    } catch (_) {
      // Keep the old row; the user can rescan.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final total = session.brand.modules.length;
    final present = _results.where((r) => r.present).toList();
    final absent = _results.where((r) => !r.present).toList();
    final faults = present.fold(0, (n, r) => n + (r.dtcs?.length ?? 0));
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_scanning) ...[
                LinearProgressIndicator(value: _results.length / total),
                const SizedBox(height: 8),
                Text('Checking ${_results.length + 1 > total ? total : _results.length + 1} of $total modules...'),
              ] else
                FilledButton.icon(
                  icon: const Icon(Icons.radar),
                  label: Text(_results.isEmpty ? 'Scan all modules' : 'Scan again'),
                  onPressed: _startScan,
                ),
              if (!_scanning && _results.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${present.length} modules found · $faults fault code(s)', textAlign: TextAlign.center),
              ],
              if (_results.isEmpty && !_scanning) ...[
                const SizedBox(height: 12),
                Text(
                  'Checks each ${session.brand.name} module for fault codes and identification. '
                  'Takes about ${(total * 1.5).round()} seconds on a real adapter.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorPanel(error: _error!),
          ),
        if (present.isNotEmpty) const SectionHeader('Modules'),
        for (final m in present)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Text(
                m.def.address.isEmpty ? m.def.name[0] : m.def.address,
                style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(m.def.name),
            subtitle: Text([m.systemName, m.partNumber].where((s) => s.isNotEmpty).join(' · ')),
            trailing: m.dtcs == null
                ? const Pill('?', color: Colors.grey)
                : m.dtcs!.isEmpty
                ? const Pill('OK', color: Colors.green)
                : Pill('${m.dtcs!.length} fault${m.dtcs!.length == 1 ? '' : 's'}', color: scheme.error),
            onTap: () => _open(m),
          ),
        if (absent.isNotEmpty && !_scanning)
          ExpansionTile(
            title: Text('Not found (${absent.length})'),
            subtitle: const Text('Not fitted to this car, or uses another address'),
            children: [
              for (final m in absent)
                ListTile(dense: true, enabled: false, leading: Text(m.def.address), title: Text(m.def.name)),
            ],
          ),
      ],
    );
  }
}
