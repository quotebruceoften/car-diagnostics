import 'dart:convert';

enum ServiceType { oil, inspection, brakeFluid, cabinFilter, airFilter, sparkPlugs, tyres, brakes, other }

extension ServiceTypeInfo on ServiceType {
  String get label => switch (this) {
    ServiceType.oil => 'Oil and filter change',
    ServiceType.inspection => 'Inspection',
    ServiceType.brakeFluid => 'Brake fluid',
    ServiceType.cabinFilter => 'Pollen filter',
    ServiceType.airFilter => 'Air filter',
    ServiceType.sparkPlugs => 'Spark plugs',
    ServiceType.tyres => 'Tyres',
    ServiceType.brakes => 'Brake pads and discs',
    ServiceType.other => 'Other',
  };

  /// Typical intervals as a starting point (months, km); the owner's manual
  /// or service booklet wins.
  ServiceInterval get defaultInterval => switch (this) {
    ServiceType.oil => const ServiceInterval(months: 12, km: 15000),
    ServiceType.inspection => const ServiceInterval(months: 24),
    ServiceType.brakeFluid => const ServiceInterval(months: 24),
    ServiceType.cabinFilter => const ServiceInterval(months: 24, km: 30000),
    ServiceType.airFilter => const ServiceInterval(months: 48, km: 60000),
    ServiceType.sparkPlugs => const ServiceInterval(months: 48, km: 60000),
    ServiceType.tyres || ServiceType.brakes || ServiceType.other => const ServiceInterval(),
  };
}

class ServiceInterval {
  const ServiceInterval({this.months, this.km});
  final int? months;
  final int? km;

  bool get isEmpty => months == null && km == null;

  Map<String, dynamic> toJson() => {'months': months, 'km': km};
  factory ServiceInterval.fromJson(Map<String, dynamic> j) =>
      ServiceInterval(months: (j['months'] as num?)?.toInt(), km: (j['km'] as num?)?.toInt());
}

class ServiceEntry {
  const ServiceEntry({
    required this.id,
    required this.type,
    required this.date,
    this.km,
    this.title = '',
    this.note = '',
    this.cost,
  });

  final String id;
  final ServiceType type;
  final DateTime date;
  final int? km;

  /// Name for "other" entries.
  final String title;
  final String note;
  final double? cost;

  String get name => type == ServiceType.other && title.isNotEmpty ? title : type.label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'date': date.toIso8601String().substring(0, 10),
    'km': km,
    'title': title,
    'note': note,
    'cost': cost,
  };

  factory ServiceEntry.fromJson(Map<String, dynamic> j) => ServiceEntry(
    id: j['id'] as String,
    type: ServiceType.values.asNameMap()[j['type']] ?? ServiceType.other,
    date: DateTime.parse(j['date'] as String),
    km: (j['km'] as num?)?.toInt(),
    title: (j['title'] ?? '') as String,
    note: (j['note'] ?? '') as String,
    cost: (j['cost'] as num?)?.toDouble(),
  );
}

enum DueStatus { ok, soon, overdue }

class Reminder {
  const Reminder({required this.type, required this.last, this.dueDate, this.dueKm, required this.status});
  final ServiceType type;
  final ServiceEntry last;
  final DateTime? dueDate;
  final int? dueKm;
  final DueStatus status;
}

/// The service history and reminder settings of one car.
class ServiceLog {
  ServiceLog({
    List<ServiceEntry>? entries,
    Map<ServiceType, ServiceInterval>? intervals,
    this.mileage,
    this.mileageDate,
  }) : entries = entries ?? [],
       intervals = intervals ?? {};

  final List<ServiceEntry> entries;

  /// Intervals the owner changed; others use [ServiceTypeInfo.defaultInterval].
  final Map<ServiceType, ServiceInterval> intervals;

  /// Last known odometer reading in km (typed in or read from the car).
  int? mileage;
  DateTime? mileageDate;

  static String pathFor(String vin) => 'service_log/${vin.isEmpty ? 'unknown' : vin}.json';

  ServiceInterval intervalOf(ServiceType t) => intervals[t] ?? t.defaultInterval;

  /// Newest first.
  List<ServiceEntry> get sorted => [...entries]..sort((a, b) => b.date.compareTo(a.date));

  /// The highest of the stored mileage and every entry's mileage.
  int? get currentKm {
    int? best = mileage;
    for (final e in entries) {
      if (e.km != null && (best == null || e.km! > best)) best = e.km;
    }
    return best;
  }

  void updateMileage(int km, DateTime when) {
    if (mileage != null && km < mileage!) return; // odometers don't go backwards
    mileage = km;
    mileageDate = when;
  }

  void upsert(ServiceEntry e) {
    entries.removeWhere((x) => x.id == e.id);
    entries.add(e);
  }

  /// Upcoming services, most urgent first.
  List<Reminder> reminders(DateTime now) {
    final out = <Reminder>[];
    final km = currentKm;
    for (final type in ServiceType.values) {
      final interval = intervalOf(type);
      if (interval.isEmpty) continue;
      ServiceEntry? last;
      for (final e in entries) {
        if (e.type == type && (last == null || e.date.isAfter(last.date))) last = e;
      }
      if (last == null) continue;
      final dueDate = interval.months == null
          ? null
          : DateTime(last.date.year, last.date.month + interval.months!, last.date.day);
      final dueKm = interval.km == null || last.km == null ? null : last.km! + interval.km!;
      var status = DueStatus.ok;
      if ((dueDate != null && !now.isBefore(dueDate)) || (dueKm != null && km != null && km >= dueKm)) {
        status = DueStatus.overdue;
      } else if ((dueDate != null && dueDate.difference(now).inDays <= 30) ||
          (dueKm != null && km != null && dueKm - km <= 1000)) {
        status = DueStatus.soon;
      }
      out.add(Reminder(type: type, last: last, dueDate: dueDate, dueKm: dueKm, status: status));
    }
    int rank(Reminder r) => switch (r.status) {
      DueStatus.overdue => 0,
      DueStatus.soon => 1,
      DueStatus.ok => 2,
    };
    out.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      if (c != 0) return c;
      return (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999));
    });
    return out;
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert({
    'entries': [for (final e in entries) e.toJson()],
    'intervals': {for (final e in intervals.entries) e.key.name: e.value.toJson()},
    'mileage': mileage,
    'mileageDate': mileageDate?.toIso8601String(),
  });

  static ServiceLog parse(String? text) {
    if (text == null) return ServiceLog();
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      final types = ServiceType.values.asNameMap();
      return ServiceLog(
        entries: [
          for (final e in (j['entries'] as List? ?? const [])) ServiceEntry.fromJson(e as Map<String, dynamic>),
        ],
        intervals: {
          for (final e in ((j['intervals'] as Map<String, dynamic>?) ?? const {}).entries)
            if (types[e.key] != null) types[e.key]!: ServiceInterval.fromJson(e.value as Map<String, dynamic>),
        },
        mileage: (j['mileage'] as num?)?.toInt(),
        mileageDate: j['mileageDate'] == null ? null : DateTime.tryParse(j['mileageDate'] as String),
      );
    } catch (_) {
      return ServiceLog();
    }
  }
}
