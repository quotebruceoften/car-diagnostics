import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../core/performance.dart';
import '../session.dart';
import '../widgets/alert_banner.dart';
import '../widgets/common.dart';

/// Turbo boost, estimated power and a shift light.
class BoostScreen extends StatefulWidget {
  const BoostScreen({super.key});

  @override
  State<BoostScreen> createState() => _BoostScreenState();
}

class _BoostScreenState extends State<BoostScreen> {
  bool? _hasMap;
  bool _hasMaf = false;
  bool _hasBaro = false;
  double _baro = 101.3; // sea level, until the car reports its own
  double? _rpm, _boost, _kw;
  double _peakBoost = double.negativeInfinity, _peakKw = 0;
  bool _polling = false;
  bool _wasOver = false;
  Object? _error;
  late DiagSession _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = SessionScope.read(context);
    if (_hasMap == null && _error == null) _setUp();
  }

  @override
  void dispose() {
    keepScreenOn(false);
    super.dispose();
  }

  Future<void> _setUp() async {
    try {
      final supported = (await _session.obd.supportedPids()).values.expand((s) => s).toSet();
      if (!mounted) return;
      setState(() {
        _hasMap = supported.contains(0x0B);
        _hasMaf = supported.contains(0x10);
        _hasBaro = supported.contains(0x33);
      });
      keepScreenOn(true);
      _poll();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<double?> _read(String pid) async {
    try {
      final r = await _session.obd.read(pid);
      _session.observe(r.pid, r.value);
      return r.numeric;
    } on NoResponseException {
      return null;
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    var loops = 0;
    try {
      while (mounted && _session.connected) {
        // Outside air pressure changes slowly (altitude), so read it now and then.
        if (_hasBaro && loops++ % 100 == 0) _baro = await _read('baro_pressure') ?? _baro;
        final rpm = await _read('rpm');
        final map = _hasMap! ? await _read('intake_map') : null;
        final maf = _hasMaf ? await _read('maf') : null;
        if (!mounted) return;
        setState(() {
          _error = null;
          _rpm = rpm ?? _rpm;
          if (map != null) {
            _boost = boostBar(map, _baro);
            _peakBoost = math.max(_peakBoost, _boost!);
          }
          if (maf != null) {
            _kw = estimatedKw(maf);
            _peakKw = math.max(_peakKw, _kw!);
          }
        });
        final over = (rpm ?? 0) >= _session.settings.shiftRpm;
        if (over && !_wasOver) HapticFeedback.heavyImpact();
        _wasOver = over;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _polling = false;
    }
  }

  Future<void> _editShiftRpm() async {
    var value = _session.settings.shiftRpm.toDouble();
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Shift light'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.round()} rpm', style: Theme.of(context).textTheme.headlineMedium),
              Slider(value: value, min: 2000, max: 7500, divisions: 55, onChanged: (v) => setState(() => value = v)),
              const Text('The screen flashes and the phone vibrates when the engine reaches this speed.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, value.round()), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (picked != null) _session.settings.setShiftRpm(picked);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SessionScope.of(context).settings;
    final shiftAt = settings.shiftRpm;
    final rpm = _rpm ?? 0;
    final over = rpm >= shiftAt;
    // Lights fill from 70% of the shift speed.
    final lit = (((rpm / shiftAt) - 0.7) / 0.3 * 8).floor().clamp(0, 8);
    final theme = Theme.of(context);
    final boost = _boost;
    return Scaffold(
      backgroundColor: over ? const Color(0xFFB71C1C) : null,
      appBar: AppBar(
        backgroundColor: over ? const Color(0xFFB71C1C) : null,
        title: const Text('Boost and shift light'),
        actions: [
          IconButton(tooltip: 'Shift light speed', icon: const Icon(Icons.tune_rounded), onPressed: _editShiftRpm),
        ],
      ),
      body: Column(
        children: [
          const AlertBanner(),
          Expanded(
            child: _hasMap == null && _error == null
                ? const LoadingView(message: 'Checking which sensors the car has...')
                : ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 32),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: ErrorPanel(error: _error!),
                        ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  for (var i = 0; i < 8; i++)
                                    Expanded(
                                      child: Container(
                                        height: 22,
                                        margin: const EdgeInsets.symmetric(horizontal: 3),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(6),
                                          color: i < lit
                                              ? (i < 4
                                                    ? const Color(0xFF2E7D32)
                                                    : i < 6
                                                    ? const Color(0xFFF9A825)
                                                    : const Color(0xFFC62828))
                                              : theme.colorScheme.surfaceContainerHighest,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              FittedBox(
                                child: Text(
                                  _rpm == null ? '–' : '${rpm.round()}',
                                  style: theme.textTheme.displayLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              Text(
                                over ? 'SHIFT' : 'rpm · shift light at $shiftAt',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_hasMap == false)
                        const StatusBanner(
                          tone: Tone.warn,
                          icon: Icons.info_outline_rounded,
                          title: 'No boost reading',
                          subtitle: "This engine doesn't report its intake manifold pressure.",
                        )
                      else
                        TileGrid(
                          children: [
                            StatTile(
                              icon: Icons.speed_rounded,
                              label: boost != null && boost < 0 ? 'Vacuum (bar)' : 'Boost (bar)',
                              value: boost == null ? '–' : boost.toStringAsFixed(2),
                              tone: boost != null && boost > 0.05 ? Tone.ok : Tone.neutral,
                            ),
                            StatTile(
                              icon: Icons.vertical_align_top_rounded,
                              label: 'Peak boost',
                              value: _peakBoost.isFinite
                                  ? '${math.max(_peakBoost, 0).toStringAsFixed(2)} bar · '
                                        '${(math.max(_peakBoost, 0) * barToPsi).toStringAsFixed(1)} psi'
                                  : '–',
                            ),
                          ],
                        ),
                      if (_hasMaf)
                        TileGrid(
                          children: [
                            StatTile(
                              icon: Icons.bolt_rounded,
                              label: 'Power now (estimate)',
                              value: _kw == null ? '–' : '${_kw!.round()} kW · ${(_kw! * kwToHp).round()} hp',
                            ),
                            StatTile(
                              icon: Icons.emoji_events_outlined,
                              label: 'Peak power (estimate)',
                              value: _peakKw <= 0 ? '–' : '${_peakKw.round()} kW · ${(_peakKw * kwToHp).round()} hp',
                            ),
                          ],
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Reset peaks'),
                          onPressed: () => setState(() {
                            _peakBoost = double.negativeInfinity;
                            _peakKw = 0;
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                        child: Text(
                          [
                            'Boost is the intake manifold pressure above the outside air pressure'
                                '${_hasBaro ? '' : ' (assumed 1.013 bar; this car does not report its own)'}.',
                            if (_hasMaf)
                              'Power is estimated from the air the engine breathes; it is only meaningful at full '
                                  'throttle and can be 10-15% off.'
                            else
                              "This engine doesn't report air flow, so power can't be estimated.",
                          ].join(' '),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
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
