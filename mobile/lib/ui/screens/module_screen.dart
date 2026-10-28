import 'package:flutter/material.dart';

import '../../brands/brand.dart';
import '../../brands/scanner.dart';
import '../../core/hex.dart';
import '../../core/obd/dtc.dart';
import '../session.dart';
import '../widgets/common.dart';
import 'coding_screen.dart';

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
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                SectionHeader(
                  'Fault codes',
                  trailing: dtcs != null && dtcs.isNotEmpty
                      ? TextButton(onPressed: () => _clear(session, info), child: const Text('Clear'))
                      : null,
                ),
                if (dtcs == null)
                  ListTile(title: const Text('Could not read fault codes'), subtitle: Text(info.error ?? ''))
                else if (dtcs.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.check, color: Colors.green),
                    title: Text('No fault codes'),
                  )
                else
                  for (final d in dtcs) _DtcTile(dtc: d, description: brand.describeDtc(d)),
                if (codingDid != null) ...[
                  const SectionHeader('Coding'),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Long coding'),
                    subtitle: Text(
                      session.profileFor(m.address, info.partNumber) != null
                          ? 'Named options available for this module'
                          : 'Byte and bit editor',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CodingScreen(module: m, did: codingDid, partNumber: info.partNumber),
                      ),
                    ),
                  ),
                ],
                const SectionHeader('Identification'),
                for (final e in brand.identificationDids.entries)
                  if (info.identification[e.key] != null)
                    ListTile(
                      dense: true,
                      title: Text(e.value),
                      subtitle: SelectableText(formatDidValue(info.identification[e.key]!)),
                    ),
                ListTile(
                  dense: true,
                  title: const Text('CAN address'),
                  subtitle: Text('${hexId(m.txId)} → ${hexId(m.rxId)}'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DtcTile extends StatelessWidget {
  const _DtcTile({required this.dtc, required this.description});
  final Dtc dtc;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(dtc.active ? Icons.error : Icons.history, color: dtc.active ? scheme.error : Colors.orange),
      title: Row(
        children: [
          Text(
            dtc.display,
            style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          Pill(dtc.active ? 'active' : 'stored', color: dtc.active ? scheme.error : Colors.orange),
        ],
      ),
      subtitle: Text('$description\n${dtc.statusFlags.join(' · ')}'),
      isThreeLine: true,
    );
  }
}
