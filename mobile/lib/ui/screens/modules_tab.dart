import 'package:flutter/material.dart';

import '../../brands/scanner.dart';
import '../scan_state.dart';
import '../session.dart';
import '../widgets/common.dart';
import 'history_screen.dart';
import 'module_screen.dart';

/// Scans the car's modules (control units) and lists their fault codes.
class ModulesTab extends StatelessWidget {
  const ModulesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return ListenableBuilder(
      listenable: session.scan,
      builder: (context, _) {
        final scan = session.scan;
        final present = scan.present;
        final absent = scan.absent;
        return ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          children: [
            ScanSummaryCard(scan: scan, onScan: () => scan.start(session.transport, session.brand)),
            Card(
              child: Row(
                children: [
                  Expanded(
                    child: ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('Scan history'),
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
                    ),
                  ),
                  if (session.lastRecord case final record? when !scan.scanning)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextButton.icon(
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('Report'),
                        onPressed: () => shareReport(context, record),
                      ),
                    ),
                ],
              ),
            ),
            if (scan.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorPanel(error: scan.error!),
              ),
            if (!scan.hasResults && !scan.scanning)
              EmptyState(
                icon: Icons.developer_board_rounded,
                title: 'Check every module',
                message:
                    'Reads the fault memory and identification of each ${session.brand.name} module: '
                    'engine, gearbox, ABS, airbags, body electronics and more.',
              ),
            if (present.isNotEmpty) ...[
              SectionHeader('Found (${present.length})'),
              Card(
                child: Column(
                  children: [
                    for (final (i, m) in present.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 76),
                      _ModuleRow(info: m),
                    ],
                  ],
                ),
              ),
            ],
            if (absent.isNotEmpty && !scan.scanning)
              Card(
                child: ExpansionTile(
                  leading: const TintedIcon(Icons.do_not_disturb_on_outlined, size: 40),
                  title: Text('Not found (${absent.length})'),
                  subtitle: const Text('Not fitted, or uses another address'),
                  children: [
                    for (final m in absent)
                      ListTile(dense: true, leading: ModuleBadge(m.def.address, dimmed: true), title: Text(m.def.name)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Scan progress / summary with the scan button. Shared with the Coding tab.
class ScanSummaryCard extends StatelessWidget {
  const ScanSummaryCard({super.key, required this.scan, required this.onScan, this.showFaults = true});
  final ScanState scan;
  final VoidCallback onScan;

  /// The Coding tab shows a neutral summary instead of the fault count.
  final bool showFaults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (scan.scanning) {
      final done = scan.results.length;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scanning modules...', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                done < scan.total ? 'Checking ${scan.total > 0 ? done + 1 : 0} of ${scan.total}' : 'Finishing',
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
    if (!scan.hasResults) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: FilledButton.icon(
          icon: const Icon(Icons.radar_rounded),
          label: const Text('Scan all modules'),
          onPressed: onScan,
        ),
      );
    }
    final faults = scan.faultCount;
    if (!showFaults) {
      return StatusBanner(
        tone: Tone.neutral,
        icon: Icons.developer_board_rounded,
        title: '${scan.present.length} modules scanned',
        subtitle: scan.finishedAt == null ? null : formatTimestamp(scan.finishedAt!),
        action: IconButton.filledTonal(
          tooltip: 'Scan again',
          onPressed: onScan,
          icon: const Icon(Icons.refresh_rounded),
        ),
      );
    }
    return StatusBanner(
      tone: faults == 0 ? Tone.ok : Tone.bad,
      icon: faults == 0 ? Icons.verified_rounded : Icons.report_problem_rounded,
      title: '${scan.present.length} modules · $faults fault${faults == 1 ? '' : 's'}',
      subtitle: scan.finishedAt == null ? null : 'Scanned ${formatTimestamp(scan.finishedAt!)}',
      action: IconButton.filledTonal(tooltip: 'Scan again', onPressed: onScan, icon: const Icon(Icons.refresh_rounded)),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.info});
  final ModuleInfo info;

  Future<void> _open(BuildContext context) async {
    final session = SessionScope.read(context);
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ModuleScreen(module: info.def)));
    // Fault codes may have been cleared or coding changed; refresh this module.
    if (!session.connected) return;
    try {
      await session.scan.refresh(session.transport, session.brand, info.def);
    } catch (_) {
      // Keep the old row; the user can rescan.
    }
  }

  @override
  Widget build(BuildContext context) {
    final dtcs = info.dtcs;
    final subtitle = [info.systemName, info.partNumber].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ModuleBadge(info.def.address.isEmpty ? info.def.name[0] : info.def.address),
      title: Text(info.def.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: dtcs == null
          ? Pill('?', color: Theme.of(context).colorScheme.outline)
          : dtcs.isEmpty
          ? Pill('OK', color: toneColor(context, Tone.ok), icon: Icons.check_rounded)
          : Pill('${dtcs.length} fault${dtcs.length == 1 ? '' : 's'}', color: toneColor(context, Tone.bad)),
      onTap: () => _open(context),
    );
  }
}
