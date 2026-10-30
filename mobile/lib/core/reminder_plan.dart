import 'service_log.dart';

/// One notification to show: at a set time, or straight away (at == null).
class PlannedNotice {
  const PlannedNotice({required this.key, required this.title, required this.body, this.at});

  /// Identifies the notice, so it is scheduled or shown only once.
  final String key;
  final String title;
  final String body;
  final DateTime? at;

  /// A stable notification id (FNV-1a of the key, 31 bits).
  int get id {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }
}

/// The notifications a service log calls for: a week before and on the day
/// a service falls due by date, and straight away when the mileage shows one
/// is close or due by distance.
List<PlannedNotice> planServiceNotices(String vin, String carName, ServiceLog log, DateTime now) {
  final out = <PlannedNotice>[];
  final km = log.currentKm;
  String day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  for (final r in log.reminders(now)) {
    final due = r.dueDate;
    if (due != null) {
      final weekBefore = DateTime(due.year, due.month, due.day - 7, 10);
      final onTheDay = DateTime(due.year, due.month, due.day, 10);
      if (weekBefore.isAfter(now)) {
        out.add(
          PlannedNotice(
            key: 'date|$vin|${r.type.name}|${day(due)}|week',
            title: '${r.type.label} due in a week',
            body: '$carName: due on ${day(due)}.',
            at: weekBefore,
          ),
        );
      }
      if (onTheDay.isAfter(now)) {
        out.add(
          PlannedNotice(
            key: 'date|$vin|${r.type.name}|${day(due)}|due',
            title: '${r.type.label} due today',
            body: '$carName: the ${r.type.label.toLowerCase()} is due today.',
            at: onTheDay,
          ),
        );
      }
    }
    final dueKm = r.dueKm;
    if (dueKm != null && km != null && dueKm - km <= 1000) {
      final over = km >= dueKm;
      out.add(
        PlannedNotice(
          key: 'km|$vin|${r.type.name}|$dueKm|${over ? 'over' : 'soon'}',
          title: over ? '${r.type.label} overdue' : '${r.type.label} due soon',
          body: over
              ? '$carName: it was due at $dueKm km; the car is at $km km.'
              : '$carName: due at $dueKm km, ${dueKm - km} km from now.',
        ),
      );
    }
  }
  return out;
}
