import 'dart:convert';

/// Fuel use per hour from the engine's air flow, for petrol engines that
/// don't report fuel rate. Stoichiometric air-fuel ratio 14.7:1 and petrol
/// density 0.745 kg/L.
double litresPerHourFromMaf(double gramsPerSecond) => gramsPerSecond * 3600 / (14.7 * 745);

enum EconomyUnit { lPer100km, kmPerL, mpgUs, mpgUk }

extension EconomyUnitText on EconomyUnit {
  String get label => switch (this) {
    EconomyUnit.lPer100km => 'L/100 km',
    EconomyUnit.kmPerL => 'km/L',
    EconomyUnit.mpgUs => 'mpg (US)',
    EconomyUnit.mpgUk => 'mpg (UK)',
  };

  /// Converts litres and kilometres into this unit; null if not meaningful.
  double? convert(double litres, double km) {
    if (km < 0.05 || litres <= 0) return null;
    return switch (this) {
      EconomyUnit.lPer100km => litres / km * 100,
      EconomyUnit.kmPerL => km / litres,
      EconomyUnit.mpgUs => (km / 1.609344) / (litres / 3.785411784),
      EconomyUnit.mpgUk => (km / 1.609344) / (litres / 4.54609),
    };
  }
}

/// Integrates distance and fuel from speed and fuel-rate samples.
class TripComputer {
  TripComputer(this.start);

  final DateTime start;
  DateTime? _last;
  double _lastSpeed = 0;
  double _lastRate = 0;

  double distanceKm = 0;
  double fuelLitres = 0;
  double maxSpeed = 0;
  Duration moving = Duration.zero;
  DateTime? end;

  /// Current fuel use, from the latest sample.
  double litresPerHour = 0;
  double speedKmh = 0;

  /// [speedKmh] and [litresPerHour] measured at [t]. Gaps longer than 10 s
  /// (adapter dropouts) are not integrated.
  void add(DateTime t, double speedKmh, double litresPerHour) {
    final last = _last;
    if (last != null) {
      final dt = t.difference(last).inMicroseconds / 3.6e9; // hours
      if (dt > 0 && dt < 10 / 3600) {
        distanceKm += (_lastSpeed + speedKmh) / 2 * dt;
        fuelLitres += (_lastRate + litresPerHour) / 2 * dt;
        if (speedKmh > 2) moving += t.difference(last);
      }
    }
    _last = t;
    _lastSpeed = speedKmh;
    _lastRate = litresPerHour;
    this.speedKmh = speedKmh;
    this.litresPerHour = litresPerHour;
    if (speedKmh > maxSpeed) maxSpeed = speedKmh;
  }

  Duration get elapsed => (end ?? _last ?? start).difference(start);

  double get averageSpeed {
    final h = moving.inMicroseconds / 3.6e9;
    return h > 0 ? distanceKm / h : 0;
  }

  TripRecord finish(DateTime t, {double? pricePerLitre}) {
    end = t;
    return TripRecord(
      start: start,
      end: t,
      distanceKm: distanceKm,
      fuelLitres: fuelLitres,
      maxSpeed: maxSpeed,
      moving: moving,
      pricePerLitre: pricePerLitre,
    );
  }
}

class TripRecord {
  const TripRecord({
    required this.start,
    required this.end,
    required this.distanceKm,
    required this.fuelLitres,
    required this.maxSpeed,
    required this.moving,
    this.pricePerLitre,
  });

  final DateTime start;
  final DateTime end;
  final double distanceKm;
  final double fuelLitres;
  final double maxSpeed;
  final Duration moving;
  final double? pricePerLitre;

  double? get cost => pricePerLitre == null ? null : fuelLitres * pricePerLitre!;
  Duration get duration => end.difference(start);

  Map<String, dynamic> toJson() => {
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'distanceKm': distanceKm,
    'fuelLitres': fuelLitres,
    'maxSpeed': maxSpeed,
    'movingSeconds': moving.inSeconds,
    'pricePerLitre': pricePerLitre,
  };

  factory TripRecord.fromJson(Map<String, dynamic> j) => TripRecord(
    start: DateTime.parse(j['start'] as String),
    end: DateTime.parse(j['end'] as String),
    distanceKm: (j['distanceKm'] as num).toDouble(),
    fuelLitres: (j['fuelLitres'] as num).toDouble(),
    maxSpeed: (j['maxSpeed'] as num? ?? 0).toDouble(),
    moving: Duration(seconds: (j['movingSeconds'] as num? ?? 0).toInt()),
    pricePerLitre: (j['pricePerLitre'] as num?)?.toDouble(),
  );

  static List<TripRecord> listFromJson(String? text) {
    if (text == null) return [];
    try {
      return [for (final t in jsonDecode(text) as List) TripRecord.fromJson(t as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }
}
