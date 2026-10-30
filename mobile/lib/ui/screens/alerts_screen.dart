import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/alerts.dart';
import '../../core/obd/pids.dart';
import '../session.dart';
import '../settings.dart';
import '../widgets/common.dart';

/// PIDs that make sense as alerts (numbers that change while driving).
final alertablePids = [
  for (final p in allPids)
    if (!const {'monitor_status', 'fuel_system', 'odometer', 'distance_mil', 'distance_since_clear'}.contains(p.name))
      p,
];

/// "above 110 °C", "below 11.8 V", "above 110 °C or below 70 °C".
String describeRule(AlertRule r, AppSettings settings) {
  final pid = pidsByName[r.pid];
  if (pid == null) return '';
  return [
    if (r.above != null) 'above ${settings.format(pid, r.above!)}',
    if (r.below != null) 'below ${settings.format(pid, r.below!)}',
  ].join(' or ');
}

/// Lets the user add, change or remove an alert for [pid]. Returns the new
/// rule list, or null when cancelled.
Future<void> editAlert(BuildContext context, Pid pid) async {
  final settings = SessionScope.read(context).settings;
  final existing = settings.alertRules.where((r) => r.pid == pid.name).firstOrNull;
  final result = await showDialog<(AlertRule?,)>(
    context: context,
    builder: (_) => _AlertDialog(pid: pid, rule: existing, settings: settings),
  );
  if (result == null) return;
  final rules = [...settings.alertRules.where((r) => r.pid != pid.name), ?result.$1];
  settings.setAlertRules(rules);
  HapticFeedback.selectionClick();
}

class _AlertDialog extends StatefulWidget {
  const _AlertDialog({required this.pid, required this.rule, required this.settings});
  final Pid pid;
  final AlertRule? rule;
  final AppSettings settings;

  @override
  State<_AlertDialog> createState() => _AlertDialogState();
}

class _AlertDialogState extends State<_AlertDialog> {
  late final _above = TextEditingController(text: _shown(widget.rule?.above));
  late final _below = TextEditingController(text: _shown(widget.rule?.below));
  String? _error;

  String _shown(double? v) {
    if (v == null) return '';
    final (shown, _) = widget.settings.convert(widget.pid, v);
    return AppSettings.number(shown);
  }

  double? _parse(String text) {
    final t = text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) throw const FormatException();
    return widget.settings.toPidUnit(widget.pid, v);
  }

  @override
  void dispose() {
    _above.dispose();
    _below.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final above = _parse(_above.text), below = _parse(_below.text);
      if (above == null && below == null) {
        Navigator.pop(context, (null,));
        return;
      }
      if (above != null && below != null && below >= above) {
        setState(() => _error = 'The lower limit must be below the upper one');
        return;
      }
      Navigator.pop(context, (AlertRule(pid: widget.pid.name, above: above, below: below),));
    } on FormatException {
      setState(() => _error = 'Enter a number');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (_, unit) = widget.settings.convert(widget.pid, widget.pid.min);
    return AlertDialog(
      title: Text(widget.pid.description),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Warn me when the value goes outside these limits. Leave a box empty for no limit.'),
          const SizedBox(height: 16),
          TextField(
            controller: _above,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: 'Warn above', suffixText: unit),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _below,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: 'Warn below', suffixText: unit, errorText: _error),
          ),
        ],
      ),
      actions: [
        if (widget.rule != null)
          TextButton(onPressed: () => Navigator.pop(context, (null,)), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Every alert, with switches to turn them on and off.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final settings = SessionScope.read(context).settings;
    final used = settings.alertRules.map((r) => r.pid).toSet();
    final pid = await showModalBottomSheet<Pid>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: ListView(
            children: [
              const ListTile(title: Text('Alert for which sensor?')),
              for (final p in alertablePids.where((p) => !used.contains(p.name)))
                ListTile(title: Text(p.description), onTap: () => Navigator.pop(context, p)),
            ],
          ),
        ),
      ),
    );
    if (pid != null && context.mounted) await editAlert(context, pid);
  }

  @override
  Widget build(BuildContext context) {
    final settings = SessionScope.of(context).settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Add alert'),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                'While live data, the dashboard or a trip is open, the phone vibrates and shows a red bar when a '
                'value crosses a limit.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (settings.alertRules.isEmpty)
              const EmptyState(icon: Icons.notifications_off_outlined, title: 'No alerts', message: 'Add one below.')
            else
              Card(
                child: Column(
                  children: [
                    for (final r in settings.alertRules)
                      if (pidsByName[r.pid] case final pid?)
                        ListTile(
                          leading: Switch(
                            value: r.enabled,
                            onChanged: (v) => settings.setAlertRules([
                              for (final x in settings.alertRules) x.pid == r.pid ? x.copyWith(enabled: v) : x,
                            ]),
                          ),
                          title: Text(pid.description),
                          subtitle: Text(describeRule(r, settings)),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => editAlert(context, pid),
                        ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
