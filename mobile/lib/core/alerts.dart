import 'package:flutter/foundation.dart';

/// Warn when a sensor goes above or below a limit. Limits are in the PID's
/// own units (°C, km/h, V).
class AlertRule {
  const AlertRule({required this.pid, this.above, this.below, this.enabled = true});

  final String pid;
  final double? above;
  final double? below;
  final bool enabled;

  bool triggeredBy(double v) => (above != null && v > above!) || (below != null && v < below!);

  /// Back inside the limits with some margin, so a value hovering at the
  /// limit doesn't alert again and again.
  bool clearedBy(double v, double margin) =>
      (above == null || v <= above! - margin) && (below == null || v >= below! + margin);

  AlertRule copyWith({double? above, double? below, bool? enabled, bool clearAbove = false, bool clearBelow = false}) =>
      AlertRule(
        pid: pid,
        above: clearAbove ? null : (above ?? this.above),
        below: clearBelow ? null : (below ?? this.below),
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {'pid': pid, 'above': above, 'below': below, 'enabled': enabled};

  static AlertRule? fromJson(Object? j) {
    if (j is! Map<String, dynamic> || j['pid'] is! String) return null;
    return AlertRule(
      pid: j['pid'] as String,
      above: (j['above'] as num?)?.toDouble(),
      below: (j['below'] as num?)?.toDouble(),
      enabled: j['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AlertRule &&
      other.pid == pid &&
      other.above == above &&
      other.below == below &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(pid, above, below, enabled);
}

/// Sensible starting alerts; the user can change or remove them.
const defaultAlertRules = [
  AlertRule(pid: 'coolant_temp', above: 110),
  AlertRule(pid: 'oil_temp', above: 135),
  AlertRule(pid: 'module_voltage', below: 11.8),
];

/// One alert that is currently firing.
class ActiveAlert {
  const ActiveAlert(this.rule, this.value, this.since);
  final AlertRule rule;
  final double value;
  final DateTime since;
}

/// Checks live readings against the rules and keeps the alerts that are on.
class AlertWatcher extends ChangeNotifier {
  AlertWatcher({this.onTriggered});

  List<AlertRule> rules = defaultAlertRules;

  /// Called once each time an alert starts (e.g. to vibrate).
  void Function(ActiveAlert alert)? onTriggered;

  final _active = <String, ActiveAlert>{};
  final _dismissed = <String>{};

  /// Alerts that are on and not dismissed by the user.
  List<ActiveAlert> get active => [
    for (final a in _active.values)
      if (!_dismissed.contains(a.rule.pid)) a,
  ];

  bool isActive(String pid) => _active.containsKey(pid);

  /// [range] is the PID's display range, used for the clearing margin.
  void report(String pid, double value, {double range = 100}) {
    AlertRule? rule;
    for (final r in rules) {
      if (r.pid == pid && r.enabled) rule = r;
    }
    final current = _active[pid];
    if (rule == null) {
      if (current != null) {
        _active.remove(pid);
        notifyListeners();
      }
      return;
    }
    if (current == null) {
      if (!rule.triggeredBy(value)) return;
      final a = _active[pid] = ActiveAlert(rule, value, DateTime.now());
      _dismissed.remove(pid);
      onTriggered?.call(a);
      notifyListeners();
    } else if (rule.clearedBy(value, range * 0.02)) {
      _active.remove(pid);
      _dismissed.remove(pid);
      notifyListeners();
    } else {
      _active[pid] = ActiveAlert(rule, value, current.since);
      notifyListeners();
    }
  }

  void dismiss(String pid) {
    if (_dismissed.add(pid)) notifyListeners();
  }

  void reset() {
    _active.clear();
    _dismissed.clear();
    notifyListeners();
  }
}
