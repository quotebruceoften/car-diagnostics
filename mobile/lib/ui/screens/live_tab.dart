import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/obd/pids.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/common.dart';
import '../widgets/sparkline.dart';
import '../widgets/skeleton.dart';
import 'dashboard_screen.dart';

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
  final _latest = <int, Object>{};
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
              _latest[p.pid] = r.value;
              final n = r.numeric;
              if (n != null) {
                final h = _history.putIfAbsent(p.pid, () => []);
                h.add(n);
                if (h.length > _historyLength) h.removeAt(0);
              }
            });
          } on NoResponseException {
            if (mounted) setState(() => _latest[p.pid] = '–');
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

  Future<void> _openDashboard() async {
    final wasPaused = _paused;
    setState(() => _paused = true); // the dashboard polls on its own
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => DashboardScreen(available: _available!)));
    if (!mounted) return;
    setState(() => _paused = wasPaused);
    if (!_paused) _poll();
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
    if (_available == null) {
      return ListView(padding: const EdgeInsets.only(top: 8), children: const [Skeleton(tiles: true, cards: 2)]);
    }
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              children: [
                _LiveDot(live: !_paused),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _paused ? 'Paused' : 'Live · ${_selected.length} sensors',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: _paused ? 'Resume' : 'Pause',
                  icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  onPressed: () {
                    setState(() => _paused = !_paused);
                    if (!_paused) _poll();
                  },
                ),
                IconButton.filledTonal(
                  tooltip: 'Driving dashboard',
                  icon: const Icon(Icons.fullscreen_rounded),
                  onPressed: _openDashboard,
                ),
                IconButton.filledTonal(
                  tooltip: 'Choose sensors',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: _choosePids,
                ),
              ],
            ),
          ),
        ),
        if (_selected.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.speed_rounded,
              title: 'No sensors selected',
              message: 'Pick the sensors you want to watch.',
              action: FilledButton(onPressed: _choosePids, child: const Text('Choose sensors')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 168,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _selected.length,
              itemBuilder: (context, i) {
                final p = _selected[i];
                return _GaugeTile(pid: p, value: _latest[p.pid], history: _history[p.pid] ?? const []);
              },
            ),
          ),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.live});
  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? toneColor(context, Tone.ok) : Theme.of(context).colorScheme.outline;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: live ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)] : null,
      ),
    );
  }
}

class _GaugeTile extends StatelessWidget {
  const _GaugeTile({required this.pid, required this.value, required this.history});
  final Pid pid;
  final Object? value;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (shown, unit) = value == null ? ('–', pid.unit) : SessionScope.of(context).settings.convert(pid, value!);
    final last = history.isEmpty ? null : history.last;
    final fraction = last == null ? 0.0 : ((last - pid.min) / (pid.max - pid.min)).clamp(0.0, 1.0);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pid.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(AppSettings.number(shown), style: theme.textTheme.headlineMedium),
                  ),
                ),
                const SizedBox(width: 4),
                Text(unit, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const Spacer(),
            Sparkline(values: history, min: pid.min, max: pid.max, height: 40),
          ],
        ),
      ),
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
