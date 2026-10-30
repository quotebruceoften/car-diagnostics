import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/service_log.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/common.dart';

String _date(DateTime d) => formatTimestamp(d).substring(0, 10);

/// Kilometres typed in the user's distance unit.
int? _parseDistance(String text, AppSettings s) {
  final v = double.tryParse(text.trim().replaceAll(',', '.').replaceAll(' ', ''));
  if (v == null) return null;
  return (s.distance == DistanceUnit.miles ? v / 0.621371 : v).round();
}

String _distanceField(int? km, AppSettings s) =>
    km == null ? '' : (s.distance == DistanceUnit.miles ? (km * 0.621371).round() : km).toString();

String _unit(AppSettings s) => s.distance == DistanceUnit.miles ? 'mi' : 'km';

/// "in 3 months", "in 12 days", "4 days ago".
String _relative(DateTime due, DateTime now) {
  final days = DateTime(due.year, due.month, due.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'today';
  final n = days.abs();
  final text = n >= 60 ? '${(n / 30.4).round()} months' : '$n day${n == 1 ? '' : 's'}';
  return days > 0 ? 'in $text' : '$text ago';
}

/// One line about when a service is due, e.g. "Due in 2 months or 1,200 km".
String describeReminder(Reminder r, ServiceLog log, AppSettings s, DateTime now) {
  final parts = <String>[];
  if (r.dueDate != null) parts.add(_relative(r.dueDate!, now));
  final km = log.currentKm;
  if (r.dueKm != null && km != null) {
    final left = r.dueKm! - km;
    parts.add(left >= 0 ? 'in ${s.km(left.toDouble(), decimals: 0)}' : '${s.km(-left.toDouble(), decimals: 0)} ago');
  } else if (r.dueKm != null) {
    parts.add('at ${s.km(r.dueKm!.toDouble(), decimals: 0)}');
  }
  final when = parts.join(' or ');
  return switch (r.status) {
    DueStatus.overdue => 'Overdue: due $when',
    DueStatus.soon => 'Due soon: $when',
    DueStatus.ok => 'Due $when',
  };
}

Tone dueTone(DueStatus s) => switch (s) {
  DueStatus.overdue => Tone.bad,
  DueStatus.soon => Tone.warn,
  DueStatus.ok => Tone.ok,
};

/// Service history and reminders for one car. Works without the adapter.
class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key, required this.vin, required this.carName});
  final String vin;
  final String carName;

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  ServiceLog? _log;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_log == null) _load();
  }

  Future<void> _load() async {
    final log = await SessionScope.read(context).loadServiceLog(widget.vin);
    if (mounted) setState(() => _log = log);
  }

  Future<void> _save() async {
    await SessionScope.read(context).saveServiceLog(widget.vin, _log!);
    if (mounted) setState(() {});
  }

  Future<void> _edit([ServiceEntry? entry]) async {
    final result = await Navigator.push<ServiceEntry>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _EntryEditor(entry: entry, currentKm: _log!.currentKm),
      ),
    );
    if (result == null) return;
    _log!.upsert(result);
    if (result.km != null) _log!.updateMileage(result.km!, result.date);
    HapticFeedback.mediumImpact();
    await _save();
  }

  Future<void> _delete(ServiceEntry e) async {
    _log!.entries.removeWhere((x) => x.id == e.id);
    await _save();
  }

  Future<void> _editMileage() async {
    final s = SessionScope.read(context).settings;
    final controller = TextEditingController(text: _distanceField(_log!.currentKm, s));
    final km = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current mileage'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Odometer', suffixText: _unit(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _parseDistance(controller.text, s)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (km == null) return;
    final log = _log!;
    if (log.mileage != null && km < log.mileage!) {
      log.mileage = km; // the owner corrects a typo
      log.mileageDate = DateTime.now();
    } else {
      log.updateMileage(km, DateTime.now());
    }
    await _save();
  }

  Future<void> _editInterval(ServiceType type) async {
    final s = SessionScope.read(context).settings;
    final current = _log!.intervalOf(type);
    final months = TextEditingController(text: current.months?.toString() ?? '');
    final distance = TextEditingController(text: _distanceField(current.km, s));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Remind me after whichever comes first. Leave a box empty to ignore it.'),
            const SizedBox(height: 16),
            TextField(
              controller: months,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Every', suffixText: 'months'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: distance,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Or every', suffixText: _unit(s)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      _log!.intervals[type] = ServiceInterval(
        months: int.tryParse(months.text.trim()),
        km: _parseDistance(distance.text, s),
      );
      await _save();
    }
    months.dispose();
    distance.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final s = session.settings;
    final theme = Theme.of(context);
    final log = _log;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Service log')),
      floatingActionButton: log == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add service'),
            ),
      body: log == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              children: [
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: const TintedIcon(Icons.directions_car_rounded, size: 44),
                    title: Text(widget.carName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      log.currentKm == null
                          ? 'Tap to enter the mileage'
                          : '${s.km(log.currentKm!.toDouble(), decimals: 0)}'
                                '${log.mileageDate == null ? '' : ' · updated ${_date(log.mileageDate!)}'}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: _editMileage,
                  ),
                ),
                if (log.reminders(now) case final reminders when reminders.isNotEmpty) ...[
                  const SectionHeader('Coming up'),
                  Card(
                    child: Column(
                      children: [
                        for (final r in reminders)
                          ListTile(
                            leading: TintedIcon(
                              r.status == DueStatus.ok ? Icons.event_available_rounded : Icons.event_busy_rounded,
                              color: toneColor(context, dueTone(r.status)),
                              size: 40,
                            ),
                            title: Text(r.type.label),
                            subtitle: Text(describeReminder(r, log, s, now)),
                            trailing: const Icon(Icons.tune_rounded),
                            onTap: () => _editInterval(r.type),
                          ),
                      ],
                    ),
                  ),
                ],
                const SectionHeader('History'),
                if (log.entries.isEmpty)
                  const EmptyState(
                    icon: Icons.build_circle_outlined,
                    title: 'No services yet',
                    message:
                        'Add the last oil change, inspection and so on. The app then reminds you when the next '
                        'one is due.',
                  )
                else
                  for (final e in log.sorted)
                    Dismissible(
                      key: ValueKey(e.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 32),
                        child: Icon(Icons.delete_outline_rounded, color: toneColor(context, Tone.bad)),
                      ),
                      onDismissed: (_) => _delete(e),
                      child: Card(
                        child: ListTile(
                          leading: const TintedIcon(Icons.build_rounded, size: 40),
                          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [
                              _date(e.date),
                              if (e.km != null) s.km(e.km!.toDouble(), decimals: 0),
                              if (e.note.isNotEmpty) e.note,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: e.cost == null ? null : Text(s.money(e.cost!), style: theme.textTheme.titleSmall),
                          onTap: () => _edit(e),
                        ),
                      ),
                    ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                  child: Text(
                    'Intervals start from typical values; tap a reminder to match your service booklet. '
                    'Reminders show here and on the Overview.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({this.entry, this.currentKm});
  final ServiceEntry? entry;
  final int? currentKm;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late ServiceType _type = widget.entry?.type ?? ServiceType.oil;
  late DateTime _date = widget.entry?.date ?? DateTime.now();
  late final _title = TextEditingController(text: widget.entry?.title ?? '');
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  late final _cost = TextEditingController(text: widget.entry?.cost?.toStringAsFixed(2) ?? '');
  TextEditingController? _km;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _km ??= TextEditingController(
      text: _distanceField(widget.entry?.km ?? widget.currentKm, SessionScope.read(context).settings),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _cost.dispose();
    _km?.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final s = SessionScope.read(context).settings;
    Navigator.pop(
      context,
      ServiceEntry(
        id: widget.entry?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        type: _type,
        date: DateTime(_date.year, _date.month, _date.day),
        km: _parseDistance(_km!.text, s),
        title: _type == ServiceType.other ? _title.text.trim() : '',
        note: _note.text.trim(),
        cost: double.tryParse(_cost.text.trim().replaceAll(',', '.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'Add service' : 'Edit service'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<ServiceType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'What was done'),
            items: [for (final t in ServiceType.values) DropdownMenuItem(value: t, child: Text(t.label))],
            onChanged: (t) => setState(() => _type = t!),
          ),
          if (_type == ServiceType.other) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
          ],
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today_rounded)),
              child: Text(formatTimestamp(_date).substring(0, 10)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _km,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Mileage', suffixText: _unit(s)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Cost (optional)', prefixText: s.currency),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (optional)', hintText: 'e.g. 5W-30 VW 504 00, garage'),
          ),
        ],
      ),
    );
  }
}
