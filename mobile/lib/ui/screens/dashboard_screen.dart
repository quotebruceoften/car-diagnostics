import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/obd/pids.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/common.dart';

const _preferred = ['rpm', 'speed', 'coolant_temp', 'engine_load', 'throttle', 'module_voltage'];

/// One recorded sample: time plus a value (in the user's units) per dial.
typedef Sample = (DateTime, List<Object?>);

/// A CSV of a recorded drive, with columns in the user's units.
String buildDriveCsv(List<Pid> pids, List<Sample> samples, AppSettings settings) {
  final header = [
    'time',
    for (final p in pids)
      settings.convert(p, p.min).$2.isEmpty ? p.name : '${p.name} (${settings.convert(p, p.min).$2})',
  ];
  final lines = [
    header.join(','),
    for (final (t, values) in samples)
      [
        t.toIso8601String(),
        for (final v in values)
          v == null
              ? ''
              : v is num
              ? AppSettings.number(v)
              : '"$v"',
      ].join(','),
  ];
  return '${lines.join('\n')}\n';
}

/// Full-screen landscape gauges for driving, with drive recording.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.available});

  /// PIDs the car supports.
  final List<Pid> available;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Preferred gauges first, then anything else the car supports.
  late final List<Pid> _dials = <Pid>{
    for (final name in _preferred)
      if (widget.available.any((p) => p.name == name)) pidsByName[name]!,
    ...widget.available,
  }.take(4).toList();
  final _values = <int, Object>{};
  final _recording = <Sample>[];
  DateTime? _recordStart;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    final session = SessionScope.read(context);
    try {
      while (mounted && session.connected) {
        for (final p in List.of(_dials)) {
          if (!mounted) return;
          try {
            final r = await session.obd.read(p.pid);
            if (mounted) setState(() => _values[p.pid] = r.value);
          } on NoResponseException {
            continue;
          }
        }
        if (_recordStart != null && mounted) {
          _recording.add((
            DateTime.now(),
            [for (final p in _dials) _values[p.pid] == null ? null : session.settings.convert(p, _values[p.pid]!).$1],
          ));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      _polling = false;
    }
  }

  Future<void> _toggleRecording() async {
    HapticFeedback.mediumImpact();
    if (_recordStart == null) {
      setState(() {
        _recording.clear();
        _recordStart = DateTime.now();
      });
      return;
    }
    final settings = SessionScope.read(context).settings;
    final csv = buildDriveCsv(_dials, _recording, settings);
    final count = _recording.length;
    setState(() => _recordStart = null);
    if (count == 0) return;
    final name = 'drive-${DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-')}.csv';
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: name)],
          fileNameOverrides: [name],
          subject: 'Drive recording ($count samples)',
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not share the recording: ${errorText(e)}');
    }
  }

  Future<void> _chooseDial(int index) async {
    final picked = await showModalBottomSheet<Pid>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: ListView(
            children: [
              for (final p in widget.available)
                ListTile(
                  title: Text(p.description),
                  trailing: p == _dials[index] ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(context, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _dials[index] = picked);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SessionScope.of(context).settings;
    final recording = _recordStart != null;
    final elapsed = recording ? DateTime.now().difference(_recordStart!) : Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close dashboard',
                    color: Colors.white70,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (recording)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          overflow: TextOverflow.ellipsis,
                          '● REC ${two(elapsed.inMinutes)}:${two(elapsed.inSeconds % 60)} · ${_recording.length} samples',
                          style: const TextStyle(color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: recording ? const Color(0xFFD32F2F) : Colors.white12,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: Icon(recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 18),
                    label: Text(recording ? 'Stop & share' : 'Record drive'),
                    onPressed: _toggleRecording,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < _dials.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _chooseDial(i),
                        child: _Dial(pid: _dials[i], value: _values[_dials[i].pid], settings: settings),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Tap a dial to change it', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({required this.pid, required this.value, required this.settings});
  final Pid pid;
  final Object? value;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final (lo, hi) = settings.range(pid);
    final (shown, unit) = value == null ? ('–', settings.convert(pid, pid.min).$2) : settings.convert(pid, value!);
    final fraction = shown is num ? ((shown.toDouble() - lo) / (hi - lo)).clamp(0.0, 1.0) : 0.0;
    final accent = Theme.of(context).colorScheme.primary;
    final color = fraction > 0.85 && (pid.name == 'rpm' || pid.name == 'coolant_temp')
        ? const Color(0xFFFF6B6B)
        : Color.lerp(accent, Colors.white, 0.35)!;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _DialPainter(fraction: fraction, color: color),
          // Keep the text inside the arc on any screen size.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 36, 40, 52),
            child: FittedBox(
              child: SizedBox(
                width: 140,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppSettings.number(shown),
                      style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800),
                    ),
                    Text(unit, style: const TextStyle(color: Colors.white60, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(
                      pid.description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  static const _start = math.pi * 0.75; // 225°: bottom left
  static const _sweep = math.pi * 1.5; // 270° arc

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, track);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * fraction,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
    final tick = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2;
    for (var i = 0; i <= 10; i++) {
      final a = _start + _sweep * i / 10;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * (radius - 18), center + dir * (radius - (i % 5 == 0 ? 28 : 22)), tick);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.fraction != fraction || old.color != color;
}
