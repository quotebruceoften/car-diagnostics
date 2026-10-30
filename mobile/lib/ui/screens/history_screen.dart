import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/history.dart';
import '../../core/obd/dtc.dart';
import '../report_pdf.dart';
import '../session.dart';
import '../widgets/common.dart';
import '../widgets/dtc_tile.dart';
import 'dtc_screen.dart';

/// Shares [record] as a PDF report through the system share sheet.
Future<void> shareReport(BuildContext context, ScanRecord record, {ScanRecord? previous}) async {
  try {
    final bytes = await buildScanReport(record, previous: previous);
    final stamp = record.timestamp.toLocal().toIso8601String().substring(0, 10);
    final name = 'scan-report-${record.vin.isEmpty ? 'car' : record.vin}-$stamp.pdf';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
        fileNameOverrides: [name],
        subject: 'Scan report: ${record.carName}',
      ),
    );
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not create the report: ${errorText(e)}');
  }
}

/// Every saved module scan of the connected car, newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Key _key = UniqueKey();

  Future<List<ScanRecord>> _load() async {
    final session = SessionScope.read(context);
    return (await session.historyStore()).list(session.vin ?? '');
  }

  Future<void> _delete(ScanRecord r) async {
    final session = SessionScope.read(context);
    await (await session.historyStore()).delete(r);
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan history')),
      body: AsyncLoader<List<ScanRecord>>(
        key: _key,
        load: _load,
        builder: (context, records, reload) {
          if (records.isEmpty) {
            return ListView(
              children: const [
                EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No scans yet',
                  message: 'Every module scan is saved here, so you can see faults come and go over time.',
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: records.length,
            itemBuilder: (context, i) {
              final r = records[i];
              final previous = i + 1 < records.length ? records[i + 1] : null;
              final cmp = previous == null ? null : ScanComparison(r, previous);
              return Dismissible(
                key: ValueKey(r.timestamp),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 32),
                  child: Icon(Icons.delete_outline_rounded, color: toneColor(context, Tone.bad)),
                ),
                onDismissed: (_) => _delete(r),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: TintedIcon(
                      r.faultCount == 0 ? Icons.verified_rounded : Icons.report_problem_rounded,
                      color: toneColor(context, r.faultCount == 0 ? Tone.ok : Tone.bad),
                      size: 40,
                    ),
                    title: Text(formatTimestamp(r.timestamp), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Pill(
                            '${r.faultCount} fault${r.faultCount == 1 ? '' : 's'}',
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          if (cmp != null && cmp.added.isNotEmpty)
                            Pill('${cmp.added.length} new', color: toneColor(context, Tone.bad)),
                          if (cmp != null && cmp.fixed.isNotEmpty)
                            Pill('${cmp.fixed.length} gone', color: toneColor(context, Tone.ok)),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ScanRecordScreen(record: r, previous: previous),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One saved scan: what was found, what changed, and a shareable report.
class ScanRecordScreen extends StatelessWidget {
  const ScanRecordScreen({super.key, required this.record, this.previous});
  final ScanRecord record;
  final ScanRecord? previous;

  @override
  Widget build(BuildContext context) {
    final cmp = previous == null ? null : ScanComparison(record, previous!);
    final withFaults = record.modules.where((m) => m.faults.isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(formatTimestamp(record.timestamp)),
        actions: [
          IconButton(
            tooltip: 'Share report',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => shareReport(context, record, previous: previous),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          StatusBanner(
            tone: record.faultCount == 0 ? Tone.ok : Tone.bad,
            icon: record.faultCount == 0 ? Icons.verified_rounded : Icons.report_problem_rounded,
            title: '${record.modules.length} modules · ${record.faultCount} faults',
            subtitle: record.carName,
          ),
          if (cmp != null) ...[
            SectionHeader('Since ${formatTimestamp(previous!.timestamp)}'),
            Card(
              child: Column(
                children: [
                  if (cmp.added.isEmpty && cmp.fixed.isEmpty) const ListTile(title: Text('No changes')),
                  for (final (module, f) in cmp.added)
                    ListTile(
                      leading: Icon(Icons.add_circle_outline_rounded, color: toneColor(context, Tone.bad)),
                      title: Text('${f.display}  ${f.description}'),
                      subtitle: Text('New · $module'),
                    ),
                  for (final (module, f) in cmp.fixed)
                    ListTile(
                      leading: Icon(Icons.check_circle_outline_rounded, color: toneColor(context, Tone.ok)),
                      title: Text('${f.display}  ${f.description}'),
                      subtitle: Text('Gone · $module'),
                    ),
                ],
              ),
            ),
          ],
          for (final m in withFaults) ...[
            SectionHeader(m.label),
            Card(
              child: Column(
                children: [
                  for (final f in m.faults)
                    DtcTile(
                      dtc: Dtc(f.code),
                      description: f.description,
                      caption: f.active == null ? null : (f.active! ? 'Active at scan time' : 'Stored'),
                      onTap: () => openDtc(context, Dtc(f.code), f.description, source: m.label),
                    ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: FilledButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Share PDF report'),
              onPressed: () => shareReport(context, record, previous: previous),
            ),
          ),
        ],
      ),
    );
  }
}
