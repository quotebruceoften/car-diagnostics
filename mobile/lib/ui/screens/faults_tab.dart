import 'package:flutter/material.dart';

import '../../core/obd/dtc.dart';
import '../../core/obd/obd_client.dart';
import '../session.dart';
import '../widgets/common.dart';

class _Faults {
  _Faults(this.byKind, this.freeze);
  final Map<DtcKind, Map<int, List<Dtc>>> byKind;
  final (String, List<Reading>)? freeze;
}

/// Emissions (OBD-II) fault codes. Per-module codes are on the Modules tab.
class FaultsTab extends StatefulWidget {
  const FaultsTab({super.key});

  @override
  State<FaultsTab> createState() => _FaultsTabState();
}

class _FaultsTabState extends State<FaultsTab> {
  Key _loaderKey = UniqueKey();

  Future<_Faults> _load(DiagSession session) async {
    final obd = session.obd;
    final byKind = {for (final k in DtcKind.values) k: await obd.readDtcs(k)};
    return _Faults(byKind, await obd.freezeFrame());
  }

  Future<void> _clear(DiagSession session) async {
    final ok = await confirm(
      context,
      title: 'Clear fault codes?',
      content: const Text(
        'This erases stored codes and freeze frame data, turns off the check engine light and resets the '
        'readiness monitors (the car may fail an emissions test until it has been driven for a while). '
        'If the fault is still there, the code will come back.\n\nThe engine should be off with the ignition on.',
      ),
      action: 'Clear codes',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final acked = await session.obd.clearDtcs();
      if (mounted) showMessage(context, 'Cleared by ${acked.map(obdEcuName).join(', ')}');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
    setState(() => _loaderKey = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return AsyncLoader<_Faults>(
      key: _loaderKey,
      load: () => _load(session),
      builder: (context, f, reload) {
        final stored = f.byKind[DtcKind.stored]!;
        final count = stored.values.fold(0, (n, l) => n + l.length);
        return RefreshIndicator(
          onRefresh: () async => setState(() => _loaderKey = UniqueKey()),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final kind in DtcKind.values) ..._section(session, kind, f.byKind[kind]!),
              if (f.freeze != null) ...[
                SectionHeader('Freeze frame (${f.freeze!.$1})'),
                for (final r in f.freeze!.$2)
                  ListTile(dense: true, title: Text(r.pid.description), trailing: Text('$r')),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(count == 0 ? 'Clear fault codes' : 'Clear $count fault code(s)'),
                  onPressed: () => _clear(session),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'These are the emissions-related codes every car reports. For airbag, ABS, body and other '
                  'modules, use the Modules tab.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _section(DiagSession session, DtcKind kind, Map<int, List<Dtc>> byEcu) {
    final (title, empty) = switch (kind) {
      DtcKind.stored => ('Stored codes', 'No stored codes'),
      DtcKind.pending => ('Pending codes', 'No pending codes'),
      DtcKind.permanent => ('Permanent codes', 'No permanent codes'),
    };
    final codes = [
      for (final e in byEcu.entries)
        for (final d in e.value) (e.key, d),
    ];
    return [
      SectionHeader(title),
      if (codes.isEmpty)
        ListTile(
          dense: true,
          leading: const Icon(Icons.check, color: Colors.green),
          title: Text(empty),
        ),
      for (final (ecu, d) in codes)
        ListTile(
          leading: Icon(
            kind == DtcKind.pending ? Icons.schedule : Icons.warning_amber,
            color: kind == DtcKind.pending ? Colors.orange : Theme.of(context).colorScheme.error,
          ),
          title: Text(
            d.code,
            style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
          ),
          subtitle: Text('${session.brand.describeDtc(d)}\n${obdEcuName(ecu)}'),
          isThreeLine: true,
        ),
    ];
  }
}
