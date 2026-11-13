import 'history.dart';
import 'obd/dtc.dart';

String _hex(int v, int digits) => v.toRadixString(16).toUpperCase().padLeft(digits, '0');

/// A plain-text file with everything a scan found, for sharing with a
/// garage or for troubleshooting: every module with its part number, and
/// every fault with the raw number and status the module sent.
String scanDetailsText(ScanRecord r, {List<String> notFound = const [], String adapter = '', String appVersion = ''}) {
  final b = StringBuffer();
  final t = r.timestamp.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  b
    ..writeln('Car Diagnostics scan details${appVersion.isEmpty ? '' : ' (app $appVersion)'}')
    ..writeln('Car: ${r.carName}')
    ..writeln('VIN: ${r.vin.isEmpty ? 'not reported' : r.vin}')
    ..writeln('Scanned: ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}')
    ..writeln('Source: ${r.source.isEmpty ? 'this app' : r.source}');
  if (adapter.isNotEmpty) b.writeln('Adapter: $adapter');
  b
    ..writeln('Modules found: ${r.modules.length}   Faults: ${r.faultCount}')
    ..writeln();
  for (final m in r.modules) {
    b.writeln('--- ${m.label}${m.partNumber.isEmpty ? '' : '   part ${m.partNumber}'}');
    if (!m.faultsReadable) {
      b.writeln('    fault memory could not be read');
    } else if (m.faults.isEmpty) {
      b.writeln('    no faults');
    }
    for (final f in m.faults) {
      b.writeln('    ${f.display}  ${f.description}');
      final details = [
        if (f.number != null) 'number ${f.number} (0x${_hex(f.number!, 6)})',
        if (f.status != null) 'status 0x${_hex(f.status!, 2)}: ${Dtc(f.code, status: f.status).statusFlags.join(', ')}',
      ];
      if (details.isNotEmpty) b.writeln('        ${details.join('   ')}');
    }
    b.writeln();
  }
  if (notFound.isNotEmpty) {
    b
      ..writeln('Modules that did not answer:')
      ..writeln('    ${notFound.join(', ')}');
  }
  return b.toString();
}
