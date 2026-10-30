import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/obd/pids.dart';

enum TempUnit { celsius, fahrenheit }

enum DistanceUnit { km, miles }

/// The adapter the user last connected to, so the app can reconnect.
class SavedAdapter {
  const SavedAdapter.ble({required this.id, required this.name}) : kind = 'ble', host = null, port = null;
  const SavedAdapter.wifi({required String this.host, required int this.port})
    : kind = 'wifi',
      id = null,
      name = 'Wi-Fi adapter';

  const SavedAdapter._(this.kind, this.id, this.name, this.host, this.port);

  final String kind;
  final String? id;
  final String name;
  final String? host;
  final int? port;

  bool get isBle => kind == 'ble';
  String get detail => isBle ? 'Bluetooth' : '$host:$port';

  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'name': name, 'host': host, 'port': port};

  static SavedAdapter? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final kind = j['kind'];
    if (kind == 'ble' && j['id'] is String) return SavedAdapter.ble(id: j['id'] as String, name: '${j['name']}');
    if (kind == 'wifi' && j['host'] is String && j['port'] is int) {
      return SavedAdapter._('wifi', null, 'Wi-Fi adapter', j['host'] as String, j['port'] as int);
    }
    return null;
  }
}

/// User preferences, saved on the phone. Without [SharedPreferences] (tests),
/// settings live in memory only.
class AppSettings extends ChangeNotifier {
  AppSettings([this._prefs]) {
    final p = _prefs;
    if (p == null) return;
    themeMode = ThemeMode.values.asNameMap()[p.getString('theme')] ?? ThemeMode.system;
    temp = TempUnit.values.asNameMap()[p.getString('temp')] ?? TempUnit.celsius;
    distance = DistanceUnit.values.asNameMap()[p.getString('distance')] ?? DistanceUnit.km;
    autoReconnect = p.getBool('autoReconnect') ?? true;
    final saved = p.getString('lastAdapter');
    try {
      lastAdapter = saved == null ? null : SavedAdapter.fromJson(jsonDecode(saved));
    } on FormatException {
      lastAdapter = null;
    }
  }

  static Future<AppSettings> load() async => AppSettings(await SharedPreferences.getInstance());

  final SharedPreferences? _prefs;

  ThemeMode themeMode = ThemeMode.system;
  TempUnit temp = TempUnit.celsius;
  DistanceUnit distance = DistanceUnit.km;
  bool autoReconnect = true;
  SavedAdapter? lastAdapter;

  void setThemeMode(ThemeMode v) => _set(() => themeMode = v, (p) => p.setString('theme', v.name));
  void setTemp(TempUnit v) => _set(() => temp = v, (p) => p.setString('temp', v.name));
  void setDistance(DistanceUnit v) => _set(() => distance = v, (p) => p.setString('distance', v.name));
  void setAutoReconnect(bool v) => _set(() => autoReconnect = v, (p) => p.setBool('autoReconnect', v));
  void setLastAdapter(SavedAdapter? a) => _set(
    () => lastAdapter = a,
    (p) => a == null ? p.remove('lastAdapter') : p.setString('lastAdapter', jsonEncode(a.toJson())),
  );

  void _set(VoidCallback change, Future<bool> Function(SharedPreferences p) persist) {
    change();
    final p = _prefs;
    if (p != null) persist(p);
    notifyListeners();
  }

  // ---------------------------------------------------------------- units

  /// Converts a value in the PID's own unit to the user's units.
  /// Returns the number (or text) to show and the unit label.
  (Object, String) convert(Pid pid, Object value) {
    if (value is! num) return (value, pid.unit);
    final v = value.toDouble();
    return switch (pid.unit) {
      '°C' when temp == TempUnit.fahrenheit => (v * 9 / 5 + 32, '°F'),
      'km/h' when distance == DistanceUnit.miles => (v * 0.621371, 'mph'),
      'km' when distance == DistanceUnit.miles => (v * 0.621371, 'mi'),
      _ => (value, pid.unit),
    };
  }

  /// Display range of a PID in the user's units (for gauges).
  (double, double) range(Pid pid) {
    final (lo, _) = convert(pid, pid.min);
    final (hi, _) = convert(pid, pid.max);
    return ((lo as num).toDouble(), (hi as num).toDouble());
  }

  /// "87", "14.1", "1730" - whole numbers without decimals.
  static String number(Object value) {
    if (value is! num) return '$value';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.abs() >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }

  /// "87 °C" / "189 °F".
  String format(Pid pid, Object value) {
    final (v, unit) = convert(pid, value);
    return unit.isEmpty ? number(v) : '${number(v)} $unit';
  }
}
