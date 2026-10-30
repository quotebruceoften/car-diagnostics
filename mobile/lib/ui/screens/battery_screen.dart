import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/battery.dart';
import '../../core/errors.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/line_chart.dart';

enum _Step { intro, resting, crankReady, cranking, charging, done }

/// A guided three-part test: battery at rest, while starting, and charging.
class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  _Step _step = _Step.intro;
  bool _busy = false;
  Object? _error;
  String? _notice;
  double? _live;

  double? _resting;
  double? _crankMin;
  bool _crankSkipped = false;
  final _crankSamples = <(DateTime, double)>[];
  double? _charging;

  @override
  void initState() {
    super.initState();
    keepScreenOn(true);
  }

  late DiagSession _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SessionScope.read(context);
  }

  @override
  void dispose() {
    keepScreenOn(false);
    // Leave the demo car running for the other screens.
    _session.demoVehicle?.engine.running = true;
    super.dispose();
  }

  Future<double> _volts() async {
    final v = await _session.batteryVoltage();
    if (v == null) throw NoResponseException('The adapter did not report a voltage');
    if (mounted) setState(() => _live = v);
    return v;
  }

  Future<double> _average(int samples, Duration gap) async {
    var sum = 0.0;
    for (var i = 0; i < samples; i++) {
      sum += await _volts();
      if (i < samples - 1) await Future<void>.delayed(gap);
    }
    return sum / samples;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _measureResting() => _run(() async {
    _session.demoVehicle?.engine.stop();
    final v = await _average(5, const Duration(milliseconds: 300));
    if (!mounted) return;
    if (v > 13.2) {
      setState(
        () => _notice =
            'That looks like the engine is running (${v.toStringAsFixed(1)} V). Turn it off, '
            'leave the ignition on, and measure again.',
      );
      return;
    }
    setState(() {
      _resting = v;
      _step = _Step.crankReady;
    });
  });

  Future<void> _measureCranking() => _run(() async {
    setState(() {
      _step = _Step.cranking;
      _crankSamples.clear();
    });
    HapticFeedback.mediumImpact();
    final demo = _session.demoVehicle;
    if (demo != null) {
      Timer(const Duration(milliseconds: 800), demo.engine.crank);
    }
    final start = DateTime.now();
    var dipped = false;
    while (mounted && DateTime.now().difference(start) < const Duration(seconds: 15)) {
      final v = await _volts();
      _crankSamples.add((DateTime.now(), v));
      if (v < _resting! - 0.5) dipped = true;
      // Started: the alternator lifts the voltage well above the battery's.
      if (dipped && v > 13.0) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!mounted) return;
    final minimum = crankingMinimum([for (final (_, v) in _crankSamples) v], _resting!);
    if (minimum == null) {
      setState(() {
        _step = _Step.crankReady;
        _notice = 'No start was detected. Press the button, then start the engine within a few seconds.';
      });
      return;
    }
    setState(() {
      _crankMin = minimum;
      _step = _Step.charging;
    });
    await _measureCharging();
  });

  void _skipCranking() => setState(() {
    _session.demoVehicle?.engine.running = true;
    _crankSkipped = true;
    _step = _Step.charging;
  });

  Future<void> _measureCharging() async {
    // Give the alternator a moment after the start.
    await Future<void>.delayed(const Duration(seconds: 3));
    final v = await _average(8, const Duration(milliseconds: 400));
    if (!mounted) return;
    if (v < 12.0) {
      setState(() => _notice = 'Is the engine running? Start it and measure again.');
      return;
    }
    setState(() {
      _charging = v;
      _step = _Step.done;
    });
    HapticFeedback.mediumImpact();
  }

  void _restart() => setState(() {
    _step = _Step.intro;
    _resting = _crankMin = _charging = null;
    _crankSkipped = false;
    _crankSamples.clear();
    _notice = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Battery and charging')),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          if (_step != _Step.done) _Progress(step: _step),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorPanel(error: _error!),
            ),
          if (_notice != null)
            StatusBanner(tone: Tone.warn, icon: Icons.info_outline_rounded, title: 'Check', subtitle: _notice!),
          ...switch (_step) {
            _Step.intro => [
              _Instruction(
                icon: Icons.battery_charging_full_rounded,
                title: 'Test your battery and alternator',
                text:
                    'Three quick measurements: the battery at rest, the dip while the engine starts, and the '
                    'charging voltage with the engine running.\n\nFor the most accurate result the car should have '
                    'been parked for an hour or more, with lights and other loads off.',
                action: FilledButton(
                  onPressed: () => setState(() => _step = _Step.resting),
                  child: const Text('Start'),
                ),
              ),
            ],
            _Step.resting => [
              _Instruction(
                icon: Icons.power_settings_new_rounded,
                title: 'Engine off, ignition on',
                text:
                    'Turn the engine off and switch the ignition on (without starting), so the adapter stays '
                    'connected. Then measure.',
                action: FilledButton(onPressed: _busy ? null : _measureResting, child: const Text('Measure')),
                busy: _busy,
                live: _live,
              ),
            ],
            _Step.crankReady => [
              _Result('At rest', _resting!, gradeResting(_resting!)),
              _Instruction(
                icon: Icons.key_rounded,
                title: 'Now start the engine',
                text:
                    'Press the button, then start the engine straight away. The app records the voltage while '
                    'the starter turns.',
                action: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(onPressed: _busy ? null : _skipCranking, child: const Text('Engine already running')),
                    FilledButton(onPressed: _busy ? null : _measureCranking, child: const Text("I'm ready")),
                  ],
                ),
              ),
            ],
            _Step.cranking => [
              _Instruction(
                icon: Icons.key_rounded,
                title: 'Start the engine now',
                text: 'Recording the voltage...',
                busy: true,
                live: _live,
              ),
            ],
            _Step.charging => [
              _Result('At rest', _resting!, gradeResting(_resting!)),
              if (_crankMin != null) _Result('While starting (lowest)', _crankMin!, gradeCranking(_crankMin!)),
              _Instruction(
                icon: Icons.electric_bolt_rounded,
                title: 'Charging',
                text: 'With the engine running at idle, measure what the alternator delivers.',
                action: FilledButton(
                  onPressed: _busy ? null : () => _run(_measureCharging),
                  child: Text(_crankSkipped ? 'Measure' : 'Measure again'),
                ),
                busy: _busy,
                live: _live,
              ),
            ],
            _Step.done => [
              _Result('At rest', _resting!, gradeResting(_resting!)),
              if (_crankMin != null) _Result('While starting (lowest)', _crankMin!, gradeCranking(_crankMin!)),
              _Result('Charging', _charging!, gradeCharging(_charging!)),
              if (_crankSamples.length > 3) ...[
                const SectionHeader('Voltage while starting'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    child: LineChart(
                      points: _crankSamples,
                      window:
                          _crankSamples.last.$1.difference(_crankSamples.first.$1) + const Duration(milliseconds: 1),
                      now: _crankSamples.last.$1,
                      limits: const [9.6],
                      height: 180,
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Test again'),
                  onPressed: _restart,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Measured at the OBD port. A battery tester at a garage measures cold cranking amps, which this '
                  'test cannot.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          },
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final index = switch (step) {
      _Step.intro => 0,
      _Step.resting => 1,
      _Step.crankReady || _Step.cranking => 2,
      _Step.charging || _Step.done => 3,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          for (var i = 1; i <= 3; i++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: i <= index ? 1 : 0, minHeight: 6),
              ),
            ),
            if (i < 3) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.busy = false,
    this.live,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  final bool busy;
  final double? live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TintedIcon(icon, size: 44),
                const SizedBox(width: 14),
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 14),
            Text(text, style: theme.textTheme.bodyLarge),
            if (busy) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 14),
                  Text(
                    live == null ? 'Measuring...' : '${live!.toStringAsFixed(1)} V',
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), Align(alignment: Alignment.centerRight, child: action)],
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result(this.label, this.volts, this.verdict);
  final String label;
  final double volts;
  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final tone = switch (verdict.grade) {
      Grade.good => Tone.ok,
      Grade.fair => Tone.warn,
      Grade.bad => Tone.bad,
    };
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TintedIcon(
              switch (verdict.grade) {
                Grade.good => Icons.check_circle_rounded,
                Grade.fair => Icons.info_rounded,
                Grade.bad => Icons.error_rounded,
              },
              color: toneColor(context, tone),
              size: 40,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(
                    '${volts.toStringAsFixed(1)} V · ${verdict.title}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(verdict.detail, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
