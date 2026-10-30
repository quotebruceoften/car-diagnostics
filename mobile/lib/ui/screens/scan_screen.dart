import 'package:flutter/material.dart';

import '../../brands/scanner.dart';
import '../scan_state.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/dtc_tile.dart';
import 'dtc_screen.dart';
import 'history_screen.dart';
import 'module_screen.dart';

/// Opens the full-car scan and starts a fresh scan.
void openScan(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ScanScreen()));

/// One place to scan every module and see every fault, grouped by module.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.startScan = true});

  /// Starts a new scan on opening (unless one is already running).
  final bool startScan;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.startScan) return;
    _started = true;
    final session = SessionScope.read(context);
    if (!session.scan.scanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  void _scan() {
    final session = SessionScope.read(context);
    if (session.connected) session.scan.start(session.transport, session.brand);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return ListenableBuilder(
      listenable: session.scan,
      builder: (context, _) {
        final scan = session.scan;
        final record = session.lastRecord;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Scan car'),
            actions: [
              IconButton(
                tooltip: 'Scan history',
                icon: const Icon(Icons.history_rounded),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
              ),
            ],
          ),
          bottomNavigationBar: scan.scanning
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        if (record != null) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Report'),
                              onPressed: () => shareReport(context, record),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.radar_rounded),
                            label: Text(scan.hasResults ? 'Scan again' : 'Start scan'),
                            onPressed: session.connected ? _scan : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              if (scan.scanning) _Progress(scan: scan) else if (scan.hasResults) _Summary(scan: scan),
              if (scan.error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorPanel(error: scan.error!),
                ),
              if (scan.scanning)
                Card(
                  child: Column(
                    children: [
                      // Modules are checked in order, so the next one is being checked now.
                      for (final (i, m) in session.brand.modules.indexed)
                        _ProgressRow(
                          address: m.address,
                          name: m.name,
                          result: scan.find(m.txId),
                          current: i == scan.results.length,
                        ),
                    ],
                  ),
                )
              else
                ..._results(context, scan),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _results(BuildContext context, ScanState scan) {
    final session = SessionScope.read(context);
    if (!scan.hasResults) {
      return [
        EmptyState(
          icon: Icons.radar_rounded,
          title: 'Scan every module',
          message:
              'Checks the fault memory of all ${session.brand.modules.length} ${session.brand.name} modules: '
              'engine, gearbox, brakes, airbags, doors, lights and more. Ignition on, engine off or running.',
        ),
      ];
    }
    final withFaults = scan.present.where((m) => (m.dtcs ?? const []).isNotEmpty).toList();
    final clean = scan.present.where((m) => m.dtcs != null && m.dtcs!.isEmpty).toList();
    final unreadable = scan.present.where((m) => m.dtcs == null).toList();
    return [
      for (final m in withFaults) ...[
        SectionHeader('${m.def.address} · ${m.def.name}'),
        Card(
          child: Column(
            children: [
              for (final d in m.dtcs!)
                DtcTile(
                  dtc: d,
                  description: session.brand.describeDtc(d),
                  onTap: () => openDtc(context, d, session.brand.describeDtc(d), source: m.def.name),
                ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.developer_board_rounded),
                title: const Text('Open module'),
                subtitle: const Text('Details, clear faults, coding'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openModule(context, m),
              ),
            ],
          ),
        ),
      ],
      if (clean.isNotEmpty || unreadable.isNotEmpty) ...[
        SectionHeader('No faults (${clean.length})'),
        Card(
          child: Column(
            children: [
              for (final m in [...clean, ...unreadable])
                ListTile(
                  leading: ModuleBadge(m.def.address),
                  title: Text(m.def.name),
                  trailing: m.dtcs == null
                      ? Pill('?', color: Theme.of(context).colorScheme.outline)
                      : Pill('OK', color: toneColor(context, Tone.ok), icon: Icons.check_rounded),
                  onTap: () => _openModule(context, m),
                ),
            ],
          ),
        ),
      ],
      if (scan.absent.isNotEmpty)
        Card(
          child: ExpansionTile(
            leading: const TintedIcon(Icons.do_not_disturb_on_outlined, size: 40),
            title: Text('Not found (${scan.absent.length})'),
            subtitle: const Text('Not fitted, or uses another address'),
            children: [
              for (final m in scan.absent)
                ListTile(dense: true, leading: ModuleBadge(m.def.address, dimmed: true), title: Text(m.def.name)),
            ],
          ),
        ),
    ];
  }

  Future<void> _openModule(BuildContext context, ModuleInfo info) async {
    final session = SessionScope.read(context);
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ModuleScreen(module: info.def)));
    if (!session.connected) return;
    try {
      await session.scan.refresh(session.transport, session.brand, info.def);
    } catch (_) {
      // Keep the old result; the user can scan again.
    }
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.scan});
  final ScanState scan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = scan.results.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Scanning...', style: theme.textTheme.titleLarge)),
                Text('$done / ${scan.total}', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${scan.present.length} modules found · ${scan.faultCount} fault${scan.faultCount == 1 ? '' : 's'} so far',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: scan.total == 0 ? null : done / scan.total, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.scan});
  final ScanState scan;

  @override
  Widget build(BuildContext context) {
    final faults = scan.faultCount;
    final withFaults = scan.present.where((m) => (m.dtcs ?? const []).isNotEmpty).length;
    return StatusBanner(
      tone: faults == 0 ? Tone.ok : Tone.bad,
      icon: faults == 0 ? Icons.verified_rounded : Icons.report_problem_rounded,
      title: faults == 0
          ? 'No faults found'
          : '$faults fault${faults == 1 ? '' : 's'} in $withFaults module${withFaults == 1 ? '' : 's'}',
      subtitle:
          '${scan.present.length} modules checked'
          '${scan.finishedAt == null ? '' : ' · ${formatTimestamp(scan.finishedAt!)}'}',
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.address, required this.name, required this.result, required this.current});
  final String address;
  final String name;
  final ModuleInfo? result;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final Widget trailing;
    final muted = Theme.of(context).textTheme.bodySmall;
    if (r == null) {
      trailing = current
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('checking', style: muted),
                const SizedBox(width: 10),
                const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            )
          : Text('waiting', style: muted);
    } else if (!r.present) {
      trailing = Text('not found', style: muted);
    } else if ((r.dtcs ?? const []).isEmpty) {
      trailing = Pill(r.dtcs == null ? '?' : 'OK', color: toneColor(context, r.dtcs == null ? Tone.neutral : Tone.ok));
    } else {
      final n = r.dtcs!.length;
      trailing = Pill('$n fault${n == 1 ? '' : 's'}', color: toneColor(context, Tone.bad));
    }
    return ListTile(
      dense: true,
      leading: ModuleBadge(address, dimmed: r == null ? !current : !r.present),
      title: Text(name),
      trailing: trailing,
    );
  }
}
