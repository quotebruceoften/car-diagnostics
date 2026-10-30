import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../brands/brand.dart';
import '../../brands/scanner.dart';
import '../../core/hex.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/dtc_tile.dart';
import 'coding_screen.dart';
import 'dtc_screen.dart';

/// One module: identification, fault codes and (where supported) coding.
class ModuleScreen extends StatefulWidget {
  const ModuleScreen({super.key, required this.module});
  final ModuleDef module;

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  Key _key = UniqueKey();

  void _reload() => setState(() => _key = UniqueKey());

  Future<void> _clear(DiagSession session, ModuleInfo info) async {
    final ok = await confirm(
      context,
      title: 'Clear fault codes?',
      content: Text('Erase the fault memory of ${widget.module.name}. Faults that are still present will come back.'),
      action: 'Clear',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ModuleScanner(session.transport, session.brand).client(widget.module).clearDtcs();
      HapticFeedback.mediumImpact();
      if (mounted) showMessage(context, 'Fault memory cleared');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final brand = session.brand;
    final m = widget.module;
    return Scaffold(
      appBar: AppBar(title: Text(m.label)),
      body: AsyncLoader<ModuleInfo>(
        key: _key,
        load: () => ModuleScanner(session.transport, brand).probe(m, full: true),
        builder: (context, info, reload) {
          if (!info.present) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [ErrorPanel(error: info.error ?? 'The module did not answer.', onRetry: _reload)],
            );
          }
          final dtcs = info.dtcs;
          final codingDid = brand.codingDidFor(m);
          final theme = Theme.of(context);
          final faults = dtcs?.length ?? 0;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        ModuleBadge(m.address.isEmpty ? m.name[0] : m.address),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name, style: theme.textTheme.titleLarge),
                              if (info.systemName.isNotEmpty || info.partNumber.isNotEmpty)
                                Text(
                                  [info.systemName, info.partNumber].where((s) => s.isNotEmpty).join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        if (dtcs != null)
                          Pill(
                            faults == 0 ? 'OK' : '$faults fault${faults == 1 ? '' : 's'}',
                            color: toneColor(context, faults == 0 ? Tone.ok : Tone.bad),
                          ),
                      ],
                    ),
                  ),
                ),
                if (codingDid != null && info.codable)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: const TintedIcon(Icons.tune_rounded, size: 40),
                      title: const Text('Long coding', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        session.profileFor(m.address, info.partNumber) != null
                            ? 'Named options available'
                            : '${info.coding!.length} bytes · bit editor',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CodingScreen(module: m, did: codingDid, partNumber: info.partNumber),
                        ),
                      ),
                    ),
                  ),
                SectionHeader(
                  'Fault codes',
                  trailing: dtcs != null && dtcs.isNotEmpty
                      ? TextButton.icon(
                          onPressed: () => _clear(session, info),
                          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                          label: const Text('Clear'),
                        )
                      : null,
                ),
                Card(
                  child: dtcs == null
                      ? ListTile(title: const Text('Could not read fault codes'), subtitle: Text(info.error ?? ''))
                      : dtcs.isEmpty
                      ? ListTile(
                          leading: Icon(Icons.check_circle_rounded, color: toneColor(context, Tone.ok)),
                          title: const Text('No fault codes'),
                        )
                      : Column(
                          children: [
                            for (final (i, d) in dtcs.indexed) ...[
                              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                              DtcTile(
                                dtc: d,
                                description: brand.describeDtc(d),
                                onTap: () => openDtc(context, d, brand.describeDtc(d), source: m.label),
                              ),
                            ],
                          ],
                        ),
                ),
                const SectionHeader('Identification'),
                Card(
                  child: Column(
                    children: [
                      for (final e in brand.identificationDids.entries)
                        if (info.identification[e.key] != null)
                          InfoRow(e.value, formatDidValue(info.identification[e.key]!), selectable: true),
                      InfoRow('CAN address', '${hexId(m.txId)} → ${hexId(m.rxId)}'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
