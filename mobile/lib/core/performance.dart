import 'dart:convert';

/// A timed speed run, e.g. 0-100 km/h or 100-0 km/h. Speeds in km/h.
class SpeedRun {
  const SpeedRun(this.from, this.to, this.label);
  final double from;
  final double to;
  final String label;

  bool get accelerating => to > from;
}

const metricRuns = [
  SpeedRun(0, 50, '0–50 km/h'),
  SpeedRun(0, 100, '0–100 km/h'),
  SpeedRun(80, 120, '80–120 km/h'),
  SpeedRun(100, 0, '100–0 km/h'),
];

const _mph = 1.609344;
const imperialRuns = [
  SpeedRun(0, 30 * _mph, '0–30 mph'),
  SpeedRun(0, 60 * _mph, '0–60 mph'),
  SpeedRun(50 * _mph, 70 * _mph, '50–70 mph'),
  SpeedRun(60 * _mph, 0, '60–0 mph'),
];

enum TimerState { waiting, armed, running, done, aborted }

/// Times a [SpeedRun] from speed samples. It starts and stops on its own,
/// so the driver never has to touch the phone. Crossing times are
/// interpolated between samples, which matters at a few samples a second.
class SpeedTimer {
  SpeedTimer(this.run);

  final SpeedRun run;
  TimerState state = TimerState.waiting;
  DateTime? startedAt;
  Duration? result;

  /// Distance covered during the run, in metres (braking distance for 100-0).
  double distanceM = 0;

  (DateTime, double)? _prev;
  double _peak = 0;

  // Speeds come as whole km/h, so a standing start is when it passes 0.5.
  double get _startLevel => run.accelerating && run.from == 0 ? 0.5 : run.from;
  double get _endLevel => !run.accelerating && run.to == 0 ? 0.5 : run.to;

  bool get finished => state == TimerState.done || state == TimerState.aborted;

  /// Seconds since the run started (live display).
  double elapsed(DateTime now) => startedAt == null ? 0 : (result ?? now.difference(startedAt!)).inMicroseconds / 1e6;

  static DateTime _cross(DateTime t0, double v0, DateTime t1, double v1, double level) {
    if (v1 == v0) return t1;
    final f = ((level - v0) / (v1 - v0)).clamp(0.0, 1.0);
    return t0.add(Duration(microseconds: (t1.difference(t0).inMicroseconds * f).round()));
  }

  void add(DateTime t, double v) {
    final prev = _prev;
    _prev = (t, v);
    switch (state) {
      case TimerState.waiting:
        final ready = run.accelerating ? (run.from == 0 ? v < 0.5 : v <= run.from - 2) : v >= run.from + 2;
        if (ready) state = TimerState.armed;
      case TimerState.armed:
        if (prev == null) return;
        final (t0, v0) = prev;
        final crossed = run.accelerating
            ? (v0 < _startLevel && v >= _startLevel)
            : (v0 > _startLevel && v <= _startLevel);
        if (!crossed) return;
        startedAt = _cross(t0, v0, t, v, _startLevel);
        state = TimerState.running;
        _peak = v;
        distanceM = (v + _startLevel) / 2 / 3.6 * t.difference(startedAt!).inMicroseconds / 1e6;
        _checkEnd(t0, v0, t, v);
      case TimerState.running:
        if (prev == null) return;
        final (t0, v0) = prev;
        distanceM += (v0 + v) / 2 / 3.6 * t.difference(t0).inMicroseconds / 1e6;
        if (_checkEnd(t0, v0, t, v)) return;
        final secs = t.difference(startedAt!).inSeconds;
        if (run.accelerating) {
          if (v > _peak) _peak = v;
          if (v < _peak - 5 || secs > 60) state = TimerState.aborted;
        } else {
          if (v > v0 + 5 || secs > 30) state = TimerState.aborted;
        }
      case TimerState.done || TimerState.aborted:
        return;
    }
  }

  bool _checkEnd(DateTime t0, double v0, DateTime t, double v) {
    final done = run.accelerating ? v >= _endLevel : v <= _endLevel;
    if (!done) return false;
    final end = _cross(t0, v0, t, v, _endLevel);
    result = end.difference(startedAt!);
    // Remove the part of the last interval after the finish line.
    final over = t.difference(end).inMicroseconds / 1e6;
    distanceM = (distanceM - (v + _endLevel) / 2 / 3.6 * over).clamp(0, double.infinity);
    state = TimerState.done;
    return true;
  }
}

class PerfResult {
  const PerfResult({required this.label, required this.seconds, required this.distanceM, required this.date});
  final String label;
  final double seconds;
  final double distanceM;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'label': label,
    'seconds': seconds,
    'distanceM': distanceM,
    'date': date.toUtc().toIso8601String(),
  };

  factory PerfResult.fromJson(Map<String, dynamic> j) => PerfResult(
    label: j['label'] as String,
    seconds: (j['seconds'] as num).toDouble(),
    distanceM: (j['distanceM'] as num? ?? 0).toDouble(),
    date: DateTime.parse(j['date'] as String),
  );

  static String pathFor(String vin) => 'performance/${vin.isEmpty ? 'unknown' : vin}.json';

  static List<PerfResult> listFromJson(String? text) {
    if (text == null) return [];
    try {
      return [for (final r in jsonDecode(text) as List) PerfResult.fromJson(r as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<PerfResult> results) => jsonEncode([for (final r in results) r.toJson()]);
}
