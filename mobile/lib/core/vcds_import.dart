/// Reads the text log that VCDS (Ross-Tech) saves after an auto-scan, so
/// scans made with VCDS join the app's scan history.
library;

import 'dart:convert';

import 'history.dart';

class VcdsLog {
  const VcdsLog(this.record, {this.mileageKm});
  final ScanRecord record;

  /// The odometer reading in the log's header, if present.
  final int? mileageKm;
}

const _months = {
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6, //
  'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12,
};

/// VCDS writes Windows-1252; newer versions may write UTF-8.
String decodeVcdsBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

final _vin = RegExp(r'VIN:\s*([A-HJ-NPR-Z0-9]{17})');
final _mileage = RegExp(r'Mileage:\s*(\d+)\s*km', caseSensitive: false);
final _address = RegExp(r'^Address ([0-9A-F]{2}):\s*(.+?)\s*(?:\(([^)]*)\))?\s*(?:Labels:.*)?$');
final _faultHeader = RegExp(r'^(\d{1,6}) - (.+)$');
final _faultDetail = RegExp(r'^\s+(?:([PCBU][0-9A-F]{4})\s+)?(?:-\s+)?([0-9A-F]{2})\s+\[([01]{8})\](?:\s+-\s*(.*))?$');

/// Parses a VCDS auto-scan log. [carName] names the car for the record
/// (e.g. from the VIN). Throws [FormatException] for other files.
VcdsLog parseVcdsLog(String text, {required String Function(String vin) carName}) {
  final lines = const LineSplitter().convert(text);
  if (!lines.take(8).any((l) => l.contains('VCDS'))) {
    throw const FormatException('This is not a VCDS scan log.');
  }
  final vin = _vin.firstMatch(text)?.group(1) ?? '';
  final mileage = int.tryParse(_mileage.firstMatch(text)?.group(1) ?? '');
  final timestamp = _timestamp(lines.first) ?? DateTime.now();

  final modules = <ModuleRecord>[];
  String? address, name, part;
  List<FaultRecord>? faults;
  var readable = false;
  String? pendingTitle, pendingNumber;

  void flushFault({String? code, String? ftb, int? status, String? detail}) {
    final title = pendingTitle;
    if (title == null || faults == null) return;
    final c = code ?? pendingNumber!;
    final description = detail == null || detail.isEmpty || detail == '-' ? title : '$title: $detail';
    faults!.add(
      FaultRecord(
        code: c,
        display: code != null && ftb != null ? '$code-$ftb' : c,
        description: description,
        active: status == null ? null : status & 0x01 != 0,
      ),
    );
    pendingTitle = pendingNumber = null;
  }

  void flushModule() {
    if (pendingTitle != null) flushFault();
    if (address != null) {
      modules.add(
        ModuleRecord(
          address: address!,
          name: name!,
          partNumber: part ?? '',
          faults: faults ?? const [],
          faultsReadable: readable,
        ),
      );
    }
    address = name = part = null;
    faults = null;
    readable = false;
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final a = _address.firstMatch(line);
    if (a != null) {
      flushModule();
      address = a.group(1);
      name = a.group(2)!.trim();
      continue;
    }
    if (address == null) continue;
    if (line.startsWith('---')) {
      flushModule();
      continue;
    }
    final trimmed = line.trim();
    if (part == null && trimmed.startsWith('Part No SW:')) {
      part = trimmed.substring('Part No SW:'.length).split(RegExp(r'\s{2,}HW:')).first.trim();
      continue;
    }
    if (trimmed == 'No fault code found.' || trimmed == 'No fault codes found.') {
      faults = [];
      readable = true;
      continue;
    }
    if (RegExp(r'^\d+ Faults? Found:$').hasMatch(trimmed)) {
      faults = [];
      readable = true;
      continue;
    }
    if (faults == null) continue;
    final header = line.startsWith(' ') ? null : _faultHeader.firstMatch(line);
    if (header != null) {
      if (pendingTitle != null) flushFault();
      pendingNumber = header.group(1);
      pendingTitle = header.group(2)!.trim();
      continue;
    }
    final detail = _faultDetail.firstMatch(line);
    if (detail != null && pendingTitle != null) {
      flushFault(
        code: detail.group(1),
        ftb: detail.group(2),
        status: int.parse(detail.group(3)!, radix: 2),
        detail: detail.group(4)?.trim(),
      );
    }
  }
  flushModule();

  if (modules.isEmpty) throw const FormatException('No modules found in this VCDS log.');
  return VcdsLog(
    ScanRecord(timestamp: timestamp, vin: vin, carName: carName(vin), modules: modules, source: 'VCDS'),
    mileageKm: mileage,
  );
}

/// "Thursday,29,October,2026,17:06:16:00009"
DateTime? _timestamp(String line) {
  final p = line.split(',');
  if (p.length < 5) return null;
  final day = int.tryParse(p[1].trim());
  final month = _months[p[2].trim().toLowerCase()];
  final year = int.tryParse(p[3].trim());
  final t = p[4].split(':');
  if (day == null || month == null || year == null || t.length < 2) return null;
  return DateTime(
    year,
    month,
    day,
    int.tryParse(t[0]) ?? 0,
    int.tryParse(t[1]) ?? 0,
    int.tryParse(t.length > 2 ? t[2] : '') ?? 0,
  );
}
