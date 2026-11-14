import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../brands/scanner.dart';
import '../../core/history.dart';
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
  FaultTrends? _trends;
  DateTime? _trendsFor;

  /// Loads the car's fault history once a scan has been saved.
  Future<void> _loadTrends(DateTime finished) async {
    if (_trendsFor == finished) return;
    _trendsFor = finished;
    final session = SessionScope.read(context);
    try {
      final records = await (await session.historyStore()).list(session.vin ?? '');
      // The newest scan may still be being saved.
      final latest = session.lastRecord;
      if (latest != null && !records.any((r) => r.timestamp.isAtSameMomentAs(latest.timestamp))) records.add(latest);
      if (mounted && records.length > 1) setState(() => _trends = FaultTrends(records));
    } catch (_) {
      // Trends are extra; the results stand on their own.
    }
  }

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

  /// The scan as it was before "Clear all", to show what came back.
  ScanRecord? _beforeClear;
  final _clearFailures = <String>[];
  bool _clearing = false;

  /// Clears the fault memory of every module that has faults, then scans
  /// again to show which faults come straight back.
  Future<void> _clearAll() async {
    final session = SessionScope.read(context);
    final withFaults = session.scan.present.where((m) => (m.dtcs ?? const []).isNotEmpty).toList();
    if (withFaults.isEmpty) return;
    final total = withFaults.fold(0, (n, m) => n + m.dtcs!.length);
    final engine = withFaults.any((m) => m.def.address == '01' || m.def.address == '02');
    final ok = await confirm(
      context,
      title: 'Clear all $total faults?',
      action: 'Clear all',
      destructive: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Erases the fault memory of ${withFaults.map((m) => m.def.name).join(', ')}.'),
          const SizedBox(height: 10),
          const Text(
            'The car is then scanned again. Faults that are still present come straight back; the rest stay '
            'away until they happen again. Modules without faults are not touched.',
          ),
          if (engine) ...[
            const SizedBox(height: 10),
            const Text(
              'This includes the engine or gearbox: their emissions self-tests start again, so the car can '
              'fail an emissions test until it has been driven for a while.',
            ),
          ],
          const SizedBox(height: 10),
          const Text('Ignition on, engine off.'),
        ],
      ),
    );
    if (!ok || !mounted || !session.connected) return;
    final before = session.lastRecord ?? session.recordFromScan();
    setState(() {
      _clearing = true;
      _clearFailures.clear();
    });
    final scanner = ModuleScanner(session.transport, session.brand);
    for (final m in withFaults) {
      try {
        await scanner.client(m.def).clearDtcs();
      } catch (e) {
        _clearFailures.add('${m.def.name}: ${errorText(e)}');
      }
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _clearing = false;
      _beforeClear = before;
    });
    _scan();
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
        if (!scan.scanning && record != null) _loadTrends(record.timestamp);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Scan car'),
            actions: [
              if (!scan.scanning && !_clearing && scan.faultCount > 0)
                IconButton(
                  tooltip: 'Clear all faults',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: session.connected ? _clearAll : null,
                ),
              IconButton(
                tooltip: 'Scan history',
                icon: const Icon(Icons.history_rounded),
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
              ),
            ],
          ),
          bottomNavigationBar: scan.scanning || _clearing
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        if (record != null) ...[
                          IconButton.outlined(
                            tooltip: 'Share details file',
                            icon: const Icon(Icons.description_outlined),
                            onPressed: () => shareScanDetails(
                              context,
                              record,
                              notFound: [for (final m in scan.absent) '${m.def.address} ${m.def.name}'],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Report'),
                              onPressed: () => shareReport(context, record),
                            ),
                          ),
                          const SizedBox(width: 8),
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
              if (_clearing)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: LoadingView(message: 'Clearing fault memories...'),
                  ),
                )
              else if (scan.scanning)
                _Progress(scan: scan)
              else if (scan.hasResults)
                _Summary(scan: scan),
              if (!scan.scanning && !_clearing) ?_clearResult(record),
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

  /// What "Clear all" achieved, once the scan after it has finished.
  Widget? _clearResult(ScanRecord? after) {
    final before = _beforeClear;
    if (before == null || after == null || !after.timestamp.isAfter(before.timestamp)) return null;
    final cleared = ScanComparison(after, before).fixed.length;
    final back = before.faultKeys.intersection(after.faultKeys).length;
    return StatusBanner(
      tone: _clearFailures.isNotEmpty ? Tone.warn : (back == 0 ? Tone.ok : Tone.neutral),
      icon: Icons.delete_sweep_rounded,
      title: back == 0 ? 'Cleared $cleared, none came back' : 'Cleared $cleared · $back came straight back',
      subtitle: [
        if (back > 0) 'The ones below are still present in the car.',
        if (_clearFailures.isNotEmpty) 'Could not clear: ${_clearFailures.join('; ')}',
      ].join(' ').emptyOrNull,
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
                Builder(
                  builder: (context) {
                    final t = _trends?.find(m.def.address, m.def.name, d.code);
                    final trend = t == null ? null : describeTrend(t);
                    // The module's full status, to tell real faults from internal entries.
                    final caption = [if (d.statusFlags.isNotEmpty) d.statusFlags.join(', '), ?trend].join(' · ');
                    return DtcTile(
                      dtc: d,
                      description: session.brand.describeDtc(d),
                      caption: caption.isEmpty ? null : caption,
                      onTap: () => openDtc(context, d, session.brand.describeDtc(d), source: m.def.name, trend: trend),
                    );
                  },
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

extension on String {
  String? get emptyOrNull => isEmpty ? null : this;
}
