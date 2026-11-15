import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/error_log.dart';
import '../core/history.dart';
import '../core/service_log.dart';
import '../core/support_report.dart';
import 'screens/settings_screen.dart' show appVersion;
import 'session.dart';
import 'widgets/common.dart';

/// Gathers everything useful for troubleshooting into one text file and
/// opens the share sheet, so it can be sent in one go.
Future<void> sendToDeveloper(BuildContext context) async {
  final session = SessionScope.read(context);
  try {
    final vin = session.vin ?? session.settings.lastCar?.vin ?? '';
    final car = session.vin != null ? session.identity.title : (session.settings.lastCar?.name ?? '');
    ScanRecord? latest = session.lastRecord;
    if (latest == null && vin.isNotEmpty) {
      final records = await (await session.historyStore()).list(vin);
      latest = records.isEmpty ? null : records.first;
    }
    final store = await session.dataStore();
    final explorer = <String, String>{};
    if (vin.isNotEmpty) {
      for (final path in await store.list('explorer/$vin')) {
        final text = await store.read(path);
        if (text != null) explorer[path.split('/').last.replaceAll('.txt', '')] = text;
      }
    }
    final backups = await (await session.backupStore()).list(vin: vin.isEmpty ? null : vin);
    final service = vin.isEmpty ? null : ServiceLog.parse(await store.read(ServiceLog.pathFor(vin)));
    final c = session.counters;
    final text = buildSupportReport(
      appVersion: appVersion,
      now: DateTime.now(),
      car: car,
      vin: vin,
      adapter: session.adapterDescription,
      connected: session.connected,
      latestScan: latest,
      notFound: session.scan.hasResults ? [for (final m in session.scan.absent) '${m.def.address} ${m.def.name}'] : [],
      explorerResults: explorer,
      codingBackups: backups,
      serviceLog: service,
      counters: c == null
          ? ''
          : [
              'odometer ${c.odometerKm} km',
              if (c.kmSinceService != null) '${c.kmSinceService} km since service reset',
              if (c.daysSinceService != null) '${c.daysSinceService} days since service reset',
            ].join(', '),
      errors: ErrorLog.instance.entries,
      settings: session.settings.toJson(),
    );
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
    final name = 'car-diagnostics-report-$stamp.txt';
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(utf8.encode(text), mimeType: 'text/plain', name: name)],
        fileNameOverrides: [name],
        subject: 'Car Diagnostics report',
      ),
    );
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not create the report: ${errorText(e)}');
  }
}
