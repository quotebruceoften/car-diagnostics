import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../core/performance.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/common.dart';

/// 0-100 km/h, 80-120 km/h and 100-0 km/h timers that start and stop
/// themselves from the car's speed.
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  SpeedRun? _run;
  SpeedTimer? _timer;
  double _speed = 0;
  double _rate = 0;
  bool _polling = false;
  Object? _error;
  List<PerfResult> _results = [];
  late DiagSession _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SessionScope.read(context);
    if (_run == null) {
      _run = _runs.first;
      _loadResults();
    }
  }

  List<SpeedRun> get _runs => _session.settings.distance == DistanceUnit.miles ? imperialRuns : metricRuns;

  @override
  void dispose() {
    _timer = null;
    keepScreenOn(false);
    super.dispose();
  }

  String get _path => PerfResult.pathFor(_session.vin ?? '');

  Future<void> _loadResults() async {
    final store = await _session.dataStore();
    final results = PerfResult.listFromJson(await store.read(_path));
    if (mounted) setState(() => _results = results.reversed.toList());
  }

  Future<void> _saveResult(PerfResult r) async {
    final store = await _session.dataStore();
    final all = [...PerfResult.listFromJson(await store.read(_path)), r];
    await store.write(_path, PerfResult.listToJson(all));
    if (mounted) setState(() => _results = all.reversed.toList());
  }

  void _arm() {
    HapticFeedback.mediumImpact();
    keepScreenOn(true);
    setState(() {
      _timer = SpeedTimer(_run!);
      _error = null;
    });
    _poll();
  }

  void _cancel() {
    keepScreenOn(false);
    setState(() => _timer = null);
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    final window = <DateTime>[];
    try {
      while (mounted && _session.connected) {
        final timer = _timer;
        if (timer == null || timer.finished) break;
        try {
          final r = await _session.obd.read('speed');
          final now = DateTime.now();
          window
            ..add(now)
            ..removeWhere((t) => now.difference(t) > const Duration(seconds: 2));
          if (!mounted || _timer != timer) break;
          final before = timer.state;
          timer.add(now, r.numeric ?? 0);
          setState(() {
            _speed = r.numeric ?? 0;
            _rate = window.length / 2;
          });
          if (before != timer.state) _onStateChange(timer);
        } on NoResponseException catch (e) {
          if (mounted) setState(() => _error = e);
        }
        // The adapter paces the loop; this only keeps a fast simulator from spinning.
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _polling = false;
    }
  }

  void _onStateChange(SpeedTimer timer) {
    switch (timer.state) {
      case TimerState.armed:
        HapticFeedback.selectionClick();
      case TimerState.running:
        HapticFeedback.heavyImpact();
      case TimerState.done:
        HapticFeedback.heavyImpact();
        keepScreenOn(false);
        _saveResult(
          PerfResult(
            label: timer.run.label,
            seconds: timer.result!.inMicroseconds / 1e6,
            distanceM: timer.distanceM,
            date: DateTime.now(),
          ),
        );
      case TimerState.aborted:
        keepScreenOn(false);
      case TimerState.waiting:
        break;
    }
  }

  String _instruction(SpeedTimer t, AppSettings s) {
    final run = t.run;
    return switch (t.state) {
      TimerState.waiting =>
        run.accelerating
            ? (run.from == 0 ? 'Bring the car to a stop' : 'Slow down below ${s.speed(run.from - 2)}')
            : 'Get up to above ${s.speed(run.from + 2)}',
      TimerState.armed =>
        run.accelerating
            ? (run.from == 0
                  ? 'Ready. The timer starts when you move.'
                  : 'Ready. Accelerate through ${s.speed(run.from)}.')
            : 'Ready. Brake when safe; timing starts at ${s.speed(run.from)}.',
      TimerState.running => 'Timing...',
      TimerState.done => run.accelerating ? 'Done' : 'Stopped in ${t.distanceM.toStringAsFixed(1)} m',
      TimerState.aborted => 'Run cancelled: the speed went the wrong way or it took too long.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = SessionScope.of(context).settings;
    final theme = Theme.of(context);
    final timer = _timer;
    final now = DateTime.now();
    final best = <String, PerfResult>{};
    for (final r in _results) {
      if (best[r.label] == null || r.seconds < best[r.label]!.seconds) best[r.label] = r;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Performance timer')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorPanel(error: _error!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _runs)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: r == _run,
                    onSelected: timer == null || timer.finished
                        ? (_) => setState(() {
                            _run = r;
                            _timer = null;
                          })
                        : null,
                  ),
              ],
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(_run!.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  FittedBox(
                    child: Text(
                      timer == null ? '0.00 s' : '${timer.elapsed(now).toStringAsFixed(2)} s',
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: timer?.state == TimerState.done ? toneColor(context, Tone.ok) : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timer == null ? 'Speed is read from the car.' : _instruction(timer, settings),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (timer != null && !timer.finished) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${settings.speed(_speed)} · ${_rate.toStringAsFixed(0)} readings/s',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: timer == null || timer.finished
                        ? FilledButton.icon(
                            icon: const Icon(Icons.flag_rounded),
                            label: Text(timer == null ? 'Get ready' : 'Run again'),
                            onPressed: _session.connected ? _arm : null,
                          )
                        : OutlinedButton(onPressed: _cancel, child: const Text('Cancel')),
                  ),
                ],
              ),
            ),
          ),
          StatusBanner(
            tone: Tone.warn,
            icon: Icons.health_and_safety_outlined,
            title: 'Only where it is safe and legal',
            subtitle:
                'Use a closed road or track, keep your eyes on the road and leave the phone in a holder. '
                'The timer starts and stops by itself.',
          ),
          if (_results.isNotEmpty) ...[
            const SectionHeader('Results'),
            Card(
              child: Column(
                children: [
                  for (final r in _results.take(20))
                    ListTile(
                      leading: best[r.label] == r
                          ? Icon(Icons.emoji_events_rounded, color: toneColor(context, Tone.warn))
                          : const Icon(Icons.timer_outlined),
                      title: Text('${r.label}: ${r.seconds.toStringAsFixed(2)} s'),
                      subtitle: Text('${formatTimestamp(r.date)} · ${r.distanceM.toStringAsFixed(0)} m'),
                    ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
            child: Text(
              'The adapter reads the speed several times a second and the app interpolates between readings; '
              'expect about ±0.2 s. The speedometer signal can differ slightly from GPS.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
