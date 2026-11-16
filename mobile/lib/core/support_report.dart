import 'dart:convert';

import 'coding/coder.dart';
import 'hex.dart';
import 'history.dart';
import 'scan_export.dart';
import 'service_log.dart';

String _stamp(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// One text file with everything useful for troubleshooting: app and car,
/// the latest scan, explorer results, coding backups, service data, recent
/// errors and settings.
String buildSupportReport({
  required String appVersion,
  required DateTime now,
  String car = '',
  String vin = '',
  String adapter = '',
  bool connected = false,
  ScanRecord? latestScan,
  List<String> notFound = const [],
  Map<String, String> explorerResults = const {},
  List<CodingBackup> codingBackups = const [],
  ServiceLog? serviceLog,
  String counters = '',
  List<(DateTime, String)> errors = const [],
  Map<String, dynamic> settings = const {},
}) {
  final b = StringBuffer();
  void section(String title) => b
    ..writeln()
    ..writeln('==== $title ====');

  b
    ..writeln('Car Diagnostics report for the developer')
    ..writeln('Created: ${_stamp(now)}   App: $appVersion')
    ..writeln('Car: ${car.isEmpty ? 'unknown' : car}')
    ..writeln('VIN: ${vin.isEmpty ? 'unknown' : vin}')
    ..writeln('Adapter: ${adapter.isEmpty ? 'not connected' : adapter}${connected ? '' : ' (not connected now)'}');
  if (counters.isNotEmpty) b.writeln('From the car: $counters');

  section('Recent errors and events (${errors.length})');
  if (errors.isEmpty) b.writeln('none');
  for (final (t, m) in errors.reversed) {
    b.writeln('${_stamp(t)}  $m');
  }

  section('Latest scan');
  if (latestScan == null) {
    b.writeln('no scan saved');
  } else {
    b.write(scanDetailsText(latestScan, notFound: notFound, appVersion: appVersion));
  }

  section('Coding backups (${codingBackups.length})');
  if (codingBackups.isEmpty) b.writeln('none');
  for (final c in codingBackups.take(30)) {
    b.writeln(
      '${_stamp(c.timestamp)}  ${c.moduleName}${c.partNumber.isEmpty ? '' : ' ${c.partNumber}'}  '
      '${bytesToHex(c.data)}',
    );
  }

  section('Service log');
  if (serviceLog == null || (serviceLog.entries.isEmpty && serviceLog.currentKm == null)) {
    b.writeln('empty');
  } else {
    b.writeln('Mileage: ${serviceLog.currentKm ?? 'unknown'} km');
    for (final e in serviceLog.sorted) {
      b.writeln('${_stamp(e.date).substring(0, 10)}  ${e.name}${e.km == null ? '' : ' at ${e.km} km'}');
    }
  }

  for (final e in explorerResults.entries) {
    section('Module explorer: ${e.key}');
    b.writeln(e.value.trimRight());
  }

  section('Settings');
  b.writeln(const JsonEncoder.withIndent('  ').convert(settings));
  return b.toString();
}
