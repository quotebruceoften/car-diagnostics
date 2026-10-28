import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/obd/pids.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/sparkline.dart';

const _defaultPids = ['rpm', 'speed', 'coolant_temp', 'engine_load', 'throttle', 'module_voltage'];
const _historyLength = 60;

/// Streams live sensor values while the tab is visible.
class LiveTab extends StatefulWidget {
  const LiveTab({super.key, required this.active});

  /// Polling only runs while the tab is on screen.
  final bool active;

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  List<Pid>? _available;
  final _selected = <Pid>[];
  final _latest = <int, String>{};
  final _history = <int, List<double>>{};
  Object? _error;
  bool _paused = false;
  bool _polling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_available == null && _error == null) _loadSupported();
  }

  @override
  void didUpdateWidget(LiveTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _poll();
  }

  Future<void> _loadSupported() async {
    final session = SessionScope.read(context);
    try {
      final supported = (await session.obd.supportedPids()).values.expand((s) => s).toSet();
      // Status PIDs (0x01, 0x03) aren't measurements, so they're not offered here.
      final available = allPids.where((p) => supported.contains(p.pid) && p.pid != 0x01 && p.pid != 0x03).toList();
      if (!mounted) return;
      setState(() {
        _available = available;
        _error = null;
        _selected
          ..clear()
          ..addAll(available.where((p) => _defaultPids.contains(p.name)));
      });
      _poll();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _poll() async {
    if (_polling || _available == null) return;
    _polling = true;
    final session = SessionScope.read(context);
    try {
      while (mounted && widget.active && !_paused && session.connected) {
        for (final p in List.of(_selected)) {
          if (!mounted || !widget.active || _paused) break;
          try {
            final r = await session.obd.read(p.pid);
            if (!mounted) break;
            setState(() {
              _latest[p.pid] = '$r';
              final n = r.numeric;
              if (n != null) {
                final h = _history.putIfAbsent(p.pid, () => []);
                h.add(n);
                if (h.length > _historyLength) h.removeAt(0);
              }
            });
          } on NoResponseException {
            if (mounted) setState(() => _latest[p.pid] = 'no reply');
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _polling = false;
    }
  }

  Future<void> _choosePids() async {
    final chosen = await showModalBottomSheet<List<Pid>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PidPicker(available: _available!, selected: _selected),
    );
    if (chosen != null) {
      setState(
        () => _selected
          ..clear()
          ..addAll(chosen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ErrorPanel(
            error: _error!,
            onRetry: () {
              setState(() => _error = null);
              _available == null ? _loadSupported() : _poll();
            },
          ),
        ],
      );
    }
    if (_available == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text('${_selected.length} sensors · ${_paused ? 'paused' : 'live'}')),
              IconButton(
                tooltip: _paused ? 'Resume' : 'Pause',
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                onPressed: () {
                  setState(() => _paused = !_paused);
                  if (!_paused) _poll();
                },
              ),
              IconButton(tooltip: 'Choose sensors', icon: const Icon(Icons.tune), onPressed: _choosePids),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _selected.length,
            itemBuilder: (context, i) {
              final p = _selected[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(p.description, style: Theme.of(context).textTheme.bodyMedium)),
                          Text(_latest[p.pid] ?? '–', style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Sparkline(values: _history[p.pid] ?? const [], min: p.min, max: p.max),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PidPicker extends StatefulWidget {
  const _PidPicker({required this.available, required this.selected});
  final List<Pid> available;
  final List<Pid> selected;

  @override
  State<_PidPicker> createState() => _PidPickerState();
}

class _PidPickerState extends State<_PidPicker> {
  late final _chosen = {...widget.selected.map((p) => p.pid)};

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          ListTile(
            title: const Text('Sensors to show'),
            subtitle: const Text('Fewer sensors update faster'),
            trailing: FilledButton(
              onPressed: () => Navigator.pop(context, widget.available.where((p) => _chosen.contains(p.pid)).toList()),
              child: const Text('Done'),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final p in widget.available)
                  CheckboxListTile(
                    value: _chosen.contains(p.pid),
                    title: Text(p.description),
                    subtitle: p.unit.isEmpty ? null : Text(p.unit),
                    onChanged: (v) => setState(() => v! ? _chosen.add(p.pid) : _chosen.remove(p.pid)),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
