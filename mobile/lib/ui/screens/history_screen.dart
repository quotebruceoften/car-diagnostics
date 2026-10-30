import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../brands/registry.dart';
import '../../core/history.dart';
import '../../core/obd/dtc.dart';
import '../../core/vcds_import.dart';
import '../report_pdf.dart';
import '../session.dart';
import '../settings.dart';
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

/// "In 3 of 4 scans since 2026-03-03", "New in this scan", "Gone since 2026-10-29".
String describeTrend(FaultTrend t) {
  String day(DateTime d) => formatTimestamp(d).substring(0, 10);
  if (!t.current) return 'Gone since ${day(t.goneSince ?? t.last)} · seen ${t.seen}×';
  if (t.seen == 1) return t.since == 1 ? 'New in the latest scan' : 'Seen once, ${day(t.first)}';
  return 'In ${t.seen} of ${t.since} scans since ${day(t.first)}';
}

/// Lets the user pick a VCDS auto-scan log and adds it to that car's history.
/// Returns the imported record.
Future<ScanRecord?> importVcdsScan(BuildContext context) async {
  final session = SessionScope.read(context);
  try {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Choose a VCDS scan log (.txt)');
    if (picked.isEmpty) return null;
    final log = parseVcdsLog(
      decodeVcdsBytes(await picked.first.readAsBytes()),
      carName: (vin) => brandForVin(vin).identify(vin).title,
    );
    final record = withBrandModuleNames(log.record);
    await (await session.historyStore()).save(record);
    if (log.mileageKm case final km? when record.vin.isNotEmpty) {
      final service = await session.loadServiceLog(record.vin);
      service.updateMileage(km, record.timestamp);
      await session.saveServiceLog(record.vin, service);
    }
    if (session.settings.lastCar == null && record.vin.isNotEmpty) {
      session.settings.setLastCar(SavedCar(vin: record.vin, name: record.carName));
    }
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      final other = session.vin != null && record.vin != session.vin;
      showMessage(
        context,
        'Imported the VCDS scan of ${formatTimestamp(record.timestamp)}: ${record.faultCount} faults in '
        '${record.modules.length} modules${other ? ' (saved to ${record.vin})' : ''}',
      );
    }
    return record;
  } on FormatException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not import: ${errorText(e)}');
  }
  return null;
}

/// Uses the app's own module names (VCDS abbreviates them, e.g. "Cent. Elect.").
ScanRecord withBrandModuleNames(ScanRecord r) {
  final names = {for (final m in brandForVin(r.vin).modules) m.address.toUpperCase(): m.name};
  return ScanRecord(
    timestamp: r.timestamp,
    vin: r.vin,
    carName: r.carName,
    source: r.source,
    modules: [
      for (final m in r.modules)
        ModuleRecord(
          address: m.address,
          name: names[m.address.toUpperCase()] ?? m.name,
          partNumber: m.partNumber,
          faults: m.faults,
          faultsReadable: m.faultsReadable,
        ),
    ],
  );
}

/// Every saved module scan of a car, newest first, with how its faults have
/// come and gone.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.vin});

  /// The car to show; defaults to the connected car.
  final String? vin;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Key _key = UniqueKey();

  String get _vin => widget.vin ?? SessionScope.read(context).vin ?? '';

  Future<List<ScanRecord>> _load() async {
    final session = SessionScope.read(context);
    return (await session.historyStore()).list(_vin);
  }

  Future<void> _import() async {
    final record = await importVcdsScan(context);
    if (record != null && mounted) setState(() => _key = UniqueKey());
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
      appBar: AppBar(
        title: const Text('Scan history'),
        actions: [
          IconButton(tooltip: 'Import a VCDS scan', icon: const Icon(Icons.upload_file_rounded), onPressed: _import),
        ],
      ),
      body: AsyncLoader<List<ScanRecord>>(
        key: _key,
        load: _load,
        builder: (context, records, reload) {
          if (records.isEmpty) {
            return ListView(
              children: [
                EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No scans yet',
                  message:
                      'Every module scan is saved here, so you can see faults come and go over time. '
                      'You can also import scans made with VCDS.',
                  action: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Import a VCDS scan'),
                    onPressed: _import,
                  ),
                ),
              ],
            );
          }
          final trends = FaultTrends(records);
          final shown = trends.all.where((t) => t.current || t.seen > 1).take(12).toList();
          final header = <Widget>[
            if (records.length > 1 && shown.isNotEmpty) ...[
              const SectionHeader('Fault trends'),
              Card(
                child: Column(
                  children: [
                    for (final t in shown)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          !t.current
                              ? Icons.check_circle_outline_rounded
                              : t.recurring
                              ? Icons.repeat_rounded
                              : Icons.fiber_new_outlined,
                          color: toneColor(context, !t.current ? Tone.ok : (t.recurring ? Tone.bad : Tone.warn)),
                        ),
                        title: Text('${t.fault.display}  ${t.fault.description}', maxLines: 2),
                        subtitle: Text('${t.moduleLabel} · ${describeTrend(t)}'),
                        onTap: () => openDtc(
                          context,
                          Dtc(t.fault.code),
                          t.fault.description,
                          source: t.moduleLabel,
                          vin: _vin,
                          trend: describeTrend(t),
                        ),
                      ),
                  ],
                ),
              ),
              const SectionHeader('Scans'),
            ],
          ];
          return ListView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            itemCount: header.length + records.length,
            itemBuilder: (context, index) {
              if (index < header.length) return header[index];
              final i = index - header.length;
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
                          if (r.source.isNotEmpty) Pill(r.source, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ScanRecordScreen(record: r, previous: previous, trends: trends),
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
  const ScanRecordScreen({super.key, required this.record, this.previous, this.trends});
  final ScanRecord record;
  final ScanRecord? previous;

  /// Trends over all the car's scans, for each fault's history.
  final FaultTrends? trends;

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
            subtitle: record.source.isEmpty ? record.carName : '${record.carName} · from ${record.source}',
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
                      caption: [
                        if (f.active != null) f.active! ? 'Active at scan time' : 'Stored',
                        if (trends?.of(m, f) case final t? when trends!.scans > 1) describeTrend(t),
                      ].join(' · ').emptyAsNull,
                      onTap: () => openDtc(
                        context,
                        Dtc(f.code),
                        f.description,
                        source: m.label,
                        vin: record.vin,
                        trend: trends?.of(m, f) == null || trends!.scans < 2 ? null : describeTrend(trends!.of(m, f)!),
                      ),
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

extension on String {
  String? get emptyAsNull => isEmpty ? null : this;
}
