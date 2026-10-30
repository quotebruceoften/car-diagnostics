import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/alerts.dart';
import '../core/obd/pids.dart';
import '../core/trip.dart';

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

/// The car last connected, so its service log is available offline.
class SavedCar {
  const SavedCar({required this.vin, required this.name});
  final String vin;
  final String name;

  Map<String, dynamic> toJson() => {'vin': vin, 'name': name};

  static SavedCar? fromJson(Object? j) =>
      j is Map<String, dynamic> && j['vin'] is String ? SavedCar(vin: j['vin'] as String, name: '${j['name']}') : null;
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
    serviceNotifications = p.getBool('serviceNotifications') ?? true;
    economy = EconomyUnit.values.asNameMap()[p.getString('economy')] ?? EconomyUnit.lPer100km;
    fuelPrice = p.getDouble('fuelPrice');
    currency = p.getString('currency') ?? '';
    lastAdapter = SavedAdapter.fromJson(_decode(p.getString('lastAdapter')));
    lastCar = SavedCar.fromJson(_decode(p.getString('lastCar')));
    final rules = _decode(p.getString('alerts'));
    if (rules is List) alertRules = [for (final r in rules) ?AlertRule.fromJson(r)];
  }

  static Object? _decode(String? text) {
    if (text == null) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static Future<AppSettings> load() async => AppSettings(await SharedPreferences.getInstance());

  final SharedPreferences? _prefs;

  ThemeMode themeMode = ThemeMode.system;
  TempUnit temp = TempUnit.celsius;
  DistanceUnit distance = DistanceUnit.km;
  bool autoReconnect = true;

  /// Phone notifications when a service falls due.
  bool serviceNotifications = true;
  SavedAdapter? lastAdapter;
  SavedCar? lastCar;
  EconomyUnit economy = EconomyUnit.lPer100km;

  /// Price of a litre of fuel, for trip costs; null until the user sets it.
  double? fuelPrice;

  /// Currency symbol shown with costs, e.g. "€" (may be empty).
  String currency = '';
  List<AlertRule> alertRules = defaultAlertRules;

  void setThemeMode(ThemeMode v) => _set(() => themeMode = v, (p) => p.setString('theme', v.name));
  void setTemp(TempUnit v) => _set(() => temp = v, (p) => p.setString('temp', v.name));
  void setDistance(DistanceUnit v) => _set(() => distance = v, (p) => p.setString('distance', v.name));
  void setAutoReconnect(bool v) => _set(() => autoReconnect = v, (p) => p.setBool('autoReconnect', v));
  void setLastAdapter(SavedAdapter? a) => _set(
    () => lastAdapter = a,
    (p) => a == null ? p.remove('lastAdapter') : p.setString('lastAdapter', jsonEncode(a.toJson())),
  );

  void setServiceNotifications(bool v) =>
      _set(() => serviceNotifications = v, (p) => p.setBool('serviceNotifications', v));
  void setLastCar(SavedCar c) => _set(() => lastCar = c, (p) => p.setString('lastCar', jsonEncode(c.toJson())));
  void setEconomy(EconomyUnit v) => _set(() => economy = v, (p) => p.setString('economy', v.name));
  void setFuelPrice(double? v, String currency) => _set(
    () {
      fuelPrice = v;
      this.currency = currency;
    },
    (p) async {
      await p.setString('currency', currency);
      return v == null ? p.remove('fuelPrice') : p.setDouble('fuelPrice', v);
    },
  );
  void setAlertRules(List<AlertRule> rules) => _set(
    () => alertRules = List.unmodifiable(rules),
    (p) => p.setString('alerts', jsonEncode([for (final r in rules) r.toJson()])),
  );

  /// "€12.40" / "12.40" when no currency is set.
  String money(double v) => '$currency${v.toStringAsFixed(2)}';

  /// Preferences worth carrying to a new phone (not the adapter, which is
  /// tied to this phone's Bluetooth).
  Map<String, dynamic> toJson() => {
    'theme': themeMode.name,
    'temp': temp.name,
    'distance': distance.name,
    'economy': economy.name,
    'autoReconnect': autoReconnect,
    'serviceNotifications': serviceNotifications,
    'fuelPrice': fuelPrice,
    'currency': currency,
    'lastCar': lastCar?.toJson(),
    'alerts': [for (final r in alertRules) r.toJson()],
  };

  void applyJson(Map<String, dynamic> j) {
    if (ThemeMode.values.asNameMap()[j['theme']] case final v?) setThemeMode(v);
    if (TempUnit.values.asNameMap()[j['temp']] case final v?) setTemp(v);
    if (DistanceUnit.values.asNameMap()[j['distance']] case final v?) setDistance(v);
    if (EconomyUnit.values.asNameMap()[j['economy']] case final v?) setEconomy(v);
    if (j['autoReconnect'] case final bool v) setAutoReconnect(v);
    if (j['serviceNotifications'] case final bool v) setServiceNotifications(v);
    if (j.containsKey('fuelPrice') || j.containsKey('currency')) {
      setFuelPrice((j['fuelPrice'] as num?)?.toDouble(), (j['currency'] ?? currency) as String);
    }
    if (SavedCar.fromJson(j['lastCar']) case final c? when lastCar == null) setLastCar(c);
    if (j['alerts'] case final List rules) setAlertRules([for (final r in rules) ?AlertRule.fromJson(r)]);
  }

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

  /// Converts a number in the user's units back to the PID's own unit.
  double toPidUnit(Pid pid, double shown) => switch (pid.unit) {
    '°C' when temp == TempUnit.fahrenheit => (shown - 32) * 5 / 9,
    'km/h' || 'km' when distance == DistanceUnit.miles => shown / 0.621371,
    _ => shown,
  };

  /// Formats a distance in km in the user's units ("87,654 km").
  String km(double km, {int decimals = 1}) {
    final miles = distance == DistanceUnit.miles;
    final v = miles ? km * 0.621371 : km;
    final text = decimals == 0 ? grouped(v.round()) : v.toStringAsFixed(decimals);
    return '$text ${miles ? 'mi' : 'km'}';
  }

  /// 87654 -> "87,654".
  static String grouped(int n) {
    final digits = n.abs().toString();
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// Formats a speed in km/h in the user's units.
  String speed(double kmh) =>
      distance == DistanceUnit.miles ? '${(kmh * 0.621371).round()} mph' : '${kmh.round()} km/h';

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
