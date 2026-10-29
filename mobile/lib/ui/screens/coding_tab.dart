import 'package:flutter/material.dart';

import '../../brands/brand.dart';
import '../../brands/scanner.dart';
import '../../core/coding/coder.dart';
import '../session.dart';
import '../widgets/common.dart';
import 'coding_screen.dart';
import 'home_screen.dart';
import 'modules_tab.dart';

/// Everything about coding in one place: which modules can be coded, which
/// have named options, and the backups taken before each write.
class CodingTab extends StatefulWidget {
  const CodingTab({super.key, required this.onNavigate});

  final void Function(int tab) onNavigate;

  @override
  State<CodingTab> createState() => _CodingTabState();
}

class _CodingTabState extends State<CodingTab> {
  List<CodingBackup>? _backups;
  String? _backupsForVin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vin = SessionScope.of(context).vin;
    if (_backups == null || vin != _backupsForVin) _loadBackups();
  }

  Future<void> _loadBackups() async {
    final session = SessionScope.read(context);
    _backupsForVin = session.vin;
    try {
      final store = await session.backupStore();
      final all = await store.list(vin: session.vin);
      if (mounted) setState(() => _backups = all);
    } catch (_) {
      if (mounted) setState(() => _backups = const []);
    }
  }

  Future<void> _openModule(ModuleDef def, String partNumber, int did) async {
    final session = SessionScope.read(context);
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CodingScreen(module: def, did: did, partNumber: partNumber),
      ),
    );
    await _loadBackups();
    if (!session.connected) return;
    try {
      await session.scan.refresh(session.transport, session.brand, def);
    } catch (_) {
      // The list keeps the previous state; a rescan fixes it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final brand = session.brand;
    if (brand.codingDid == null) {
      return ListView(
        children: [
          EmptyState(
            icon: Icons.tune_rounded,
            title: 'Coding not available for ${brand.name}',
            message:
                'Coding is supported for Volkswagen Group cars (VW, Audi, Škoda, SEAT, Cupra). '
                'If this is one, choose the make with the ⇄ button at the top.',
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: session.scan,
      builder: (context, _) {
        final scan = session.scan;
        final codable = scan.codable;
        return RefreshIndicator(
          onRefresh: _loadBackups,
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              const _SafetyCard(),
              if (!scan.hasResults && !scan.scanning)
                EmptyState(
                  icon: Icons.tune_rounded,
                  title: 'Find codable modules',
                  message: 'Scan the car to see which modules can be coded and which have named options.',
                  action: FilledButton.icon(
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('Scan modules'),
                    onPressed: () => scan.start(session.transport, brand),
                  ),
                )
              else
                ScanSummaryCard(scan: scan, showFaults: false, onScan: () => scan.start(session.transport, brand)),
              if (scan.hasResults && !scan.scanning && codable.isEmpty)
                const EmptyState(
                  icon: Icons.block_rounded,
                  title: 'No codable modules found',
                  message: 'None of the modules reported a coding value.',
                ),
              if (codable.isNotEmpty) ...[
                SectionHeader('Codable modules (${codable.length})'),
                Card(
                  child: Column(
                    children: [
                      for (final (i, m) in codable.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 76),
                        _CodableRow(
                          info: m,
                          hasProfile: session.profileFor(m.def.address, m.partNumber)?.length == m.coding!.length,
                          backups: _backups?.where((b) => b.txId == m.def.txId).length ?? 0,
                          onTap: () => _openModule(m.def, m.partNumber, brand.codingDidFor(m.def)!),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_backups != null && _backups!.isNotEmpty) ...[
                SectionHeader('Recent backups'),
                Card(
                  child: Column(
                    children: [
                      for (final b in _backups!.take(6))
                        ListTile(
                          leading: const TintedIcon(Icons.history_rounded, size: 40),
                          title: Text(b.moduleName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(formatTimestamp(b.timestamp)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openBackupModule(b),
                        ),
                    ],
                  ),
                ),
              ],
              if (!scan.hasResults)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton.icon(
                    icon: const Icon(Icons.developer_board_rounded),
                    label: const Text('Go to the module list'),
                    onPressed: () => widget.onNavigate(HomeTabs.modules),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openBackupModule(CodingBackup b) {
    final session = SessionScope.read(context);
    final def = session.brand.modules.where((m) => m.txId == b.txId).firstOrNull;
    if (def == null) {
      showMessage(context, 'That module is not part of the ${session.brand.name} module list.');
      return;
    }
    final info = session.scan.find(def.txId);
    _openModule(def, info?.partNumber ?? b.partNumber, b.did);
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TintedIcon(Icons.shield_outlined, color: toneColor(context, Tone.ok), size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backed up before every change', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Each write is read back to confirm it worked, and old coding can be restored from the module '
                    "screen. Keep the ignition on and only change bits you've confirmed for your module.",
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

class _CodableRow extends StatelessWidget {
  const _CodableRow({required this.info, required this.hasProfile, required this.backups, required this.onTap});
  final ModuleInfo info;
  final bool hasProfile;
  final int backups;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            ModuleBadge(info.def.address.isEmpty ? info.def.name[0] : info.def.address),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.def.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [info.partNumber, '${info.coding!.length} bytes'].where((s) => s.isNotEmpty).join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      hasProfile
                          ? Pill('Named options', color: toneColor(context, Tone.ok), icon: Icons.check_rounded)
                          : Pill('Bit editor', color: theme.colorScheme.onSurfaceVariant),
                      if (backups > 0)
                        Pill(
                          '$backups backup${backups == 1 ? '' : 's'}',
                          color: theme.colorScheme.primary,
                          icon: Icons.history_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
