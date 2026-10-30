import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/obd/pids.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/alert_banner.dart';
import '../widgets/common.dart';
import '../widgets/line_chart.dart';
import 'alerts_screen.dart';

typedef TimedValue = (DateTime, double);

const _windows = [Duration(seconds: 30), Duration(minutes: 2), Duration(minutes: 10)];

/// One sensor in detail: a scrolling graph, statistics and its alert.
class SensorScreen extends StatefulWidget {
  const SensorScreen({super.key, required this.pid, this.history = const []});

  final Pid pid;

  /// Values already collected by the Live tab, in the PID's own unit.
  final List<TimedValue> history;

  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  late final List<TimedValue> _points = [...widget.history];
  Duration _window = _windows[1];
  bool _polling = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    final session = SessionScope.read(context);
    try {
      while (mounted && session.connected) {
        try {
          final r = await session.obd.read(widget.pid.pid);
          session.observe(r.pid, r.value);
          final n = r.numeric;
          if (n != null && mounted) {
            setState(() {
              _points.add((DateTime.now(), n));
              final cutoff = DateTime.now().subtract(_windows.last);
              while (_points.isNotEmpty && _points.first.$1.isBefore(cutoff)) {
                _points.removeAt(0);
              }
              _error = null;
            });
          }
        } on NoResponseException catch (e) {
          if (mounted) setState(() => _error = e);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final settings = session.settings;
    final pid = widget.pid;
    final theme = Theme.of(context);
    final now = DateTime.now();
    double shown(double v) => (settings.convert(pid, v).$1 as num).toDouble();
    final (_, unit) = settings.convert(pid, pid.min);
    final converted = [for (final (t, v) in _points) (t, shown(v))];
    final inWindow = [
      for (final (t, v) in converted)
        if (!t.isBefore(now.subtract(_window))) v,
    ];
    final rule = settings.alertRules.where((r) => r.pid == pid.name && r.enabled).firstOrNull;
    String fmt(double v) => '${AppSettings.number(double.parse(v.toStringAsFixed(1)))} $unit';

    return Scaffold(
      appBar: AppBar(title: Text(pid.description)),
      body: Column(
        children: [
          const AlertBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 32),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ErrorPanel(error: _error!),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              converted.isEmpty ? '–' : AppSettings.number(converted.last.$2),
                              style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 6),
                            Text(unit, style: theme.textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LineChart(
                          points: converted,
                          window: _window,
                          now: now,
                          limits: [if (rule?.above case final a?) shown(a), if (rule?.below case final b?) shown(b)],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<Duration>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: Duration(seconds: 30), label: Text('30 s')),
                              ButtonSegment(value: Duration(minutes: 2), label: Text('2 min')),
                              ButtonSegment(value: Duration(minutes: 10), label: Text('10 min')),
                            ],
                            selected: {_window},
                            onSelectionChanged: (s) => setState(() => _window = s.first),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TileGrid(
                  children: [
                    StatTile(
                      icon: Icons.arrow_downward_rounded,
                      label: 'Lowest',
                      value: inWindow.isEmpty ? '–' : fmt(inWindow.reduce(math.min)),
                    ),
                    StatTile(
                      icon: Icons.arrow_upward_rounded,
                      label: 'Highest',
                      value: inWindow.isEmpty ? '–' : fmt(inWindow.reduce(math.max)),
                    ),
                    StatTile(
                      icon: Icons.functions_rounded,
                      label: 'Average',
                      value: inWindow.isEmpty ? '–' : fmt(inWindow.reduce((a, b) => a + b) / inWindow.length),
                    ),
                    StatTile(icon: Icons.timeline_rounded, label: 'Samples', value: '${inWindow.length}'),
                  ],
                ),
                const SectionHeader('Alert'),
                Card(
                  child: ListTile(
                    leading: TintedIcon(
                      rule == null ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                      size: 40,
                    ),
                    title: Text(rule == null ? 'No alert' : 'Warn ${describeRule(rule, settings)}'),
                    subtitle: const Text('Vibrate and show a red bar when the value crosses a limit'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => editAlert(context, pid),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
