import 'package:flutter/material.dart';

import '../../core/obd/dtc.dart';
import '../../core/obd/obd_client.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/dtc_tile.dart';

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

  void _reload() => setState(() => _loaderKey = UniqueKey());

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
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return AsyncLoader<_Faults>(
      key: _loaderKey,
      load: () => _load(session),
      builder: (context, f, reload) {
        int count(DtcKind k) => f.byKind[k]!.values.fold(0, (n, l) => n + l.length);
        final stored = count(DtcKind.stored), pending = count(DtcKind.pending);
        final total = stored + pending + count(DtcKind.permanent);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              StatusBanner(
                tone: stored > 0 ? Tone.bad : (pending > 0 ? Tone.warn : Tone.ok),
                icon: total == 0 ? Icons.check_circle_rounded : Icons.report_problem_rounded,
                title: total == 0 ? 'No fault codes' : '$total fault code${total == 1 ? '' : 's'}',
                subtitle: total == 0
                    ? 'The engine computers report no emissions faults'
                    : '$stored stored · $pending pending',
              ),
              for (final kind in DtcKind.values) ..._section(session, kind, f.byKind[kind]!),
              if (f.freeze != null) ...[
                SectionHeader('Freeze frame · ${f.freeze!.$1}'),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Text(
                          'Conditions when ${f.freeze!.$1} was stored',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      for (final r in f.freeze!.$2) InfoRow(r.pid.description, '$r'),
                    ],
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: Text(stored == 0 ? 'Clear fault codes' : 'Clear $stored fault code${stored == 1 ? '' : 's'}'),
                  onPressed: () => _clear(session),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'These are the emissions codes every car reports. For airbag, ABS, body and other modules, '
                  'use the Modules tab.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _section(DiagSession session, DtcKind kind, Map<int, List<Dtc>> byEcu) {
    final codes = [
      for (final e in byEcu.entries)
        for (final d in e.value) (e.key, d),
    ];
    if (codes.isEmpty) return const [];
    final title = switch (kind) {
      DtcKind.stored => 'Stored',
      DtcKind.pending => 'Pending',
      DtcKind.permanent => 'Permanent',
    };
    return [
      SectionHeader('$title (${codes.length})'),
      Card(
        child: Column(
          children: [
            for (final (ecu, d) in codes)
              DtcTile(
                dtc: d,
                description: session.brand.describeDtc(d),
                tone: kind == DtcKind.pending ? Tone.warn : Tone.bad,
                caption: obdEcuName(ecu),
              ),
          ],
        ),
      ),
    ];
  }
}
