import 'dart:typed_data';

import '../errors.dart';
import '../hex.dart';
import 'uds_client.dart';

/// One data item a module answered with.
class ExploredItem {
  const ExploredItem(this.did, this.data);
  final int did;
  final Uint8List data;

  String get id => did.toRadixString(16).toUpperCase().padLeft(4, '0');
  String get hex => bytesToHex(data, separator: ' ');

  /// The bytes as text, when they are all printable characters.
  String? get text {
    if (data.isEmpty || data.any((b) => b < 0x20 || b > 0x7E)) return null;
    final t = String.fromCharCodes(data).trim();
    return t.isEmpty ? null : t;
  }

  /// The bytes as one whole number, for values of up to four bytes.
  int? get number => data.isEmpty || data.length > 4 ? null : data.fold<int>(0, (v, b) => (v << 8) | b);

  Map<String, dynamic> toJson() => {'did': id, 'hex': bytesToHex(data)};
}

/// A range of data identifiers to ask for.
class ExploreRange {
  const ExploreRange(this.first, this.last);
  final int first;
  final int last;
  int get count => last - first + 1;
}

class ExplorePreset {
  const ExplorePreset(this.name, this.description, this.ranges);
  final String name;
  final String description;
  final List<ExploreRange> ranges;

  int get count => ranges.fold(0, (n, r) => n + r.count);
}

const explorePresets = [
  ExplorePreset('Quick', 'Identification and the usual places for settings', [
    ExploreRange(0xF100, 0xF1FF),
    ExploreRange(0x0100, 0x06FF),
  ]),
  ExplorePreset('Thorough', 'Most places modules keep live values', [
    ExploreRange(0x0000, 0x2FFF),
    ExploreRange(0xF000, 0xFFFF),
  ]),
  ExplorePreset('The rest', 'What Thorough leaves out', [ExploreRange(0x3000, 0xEFFF)]),
  ExplorePreset('Everything', 'Every possible item', [ExploreRange(0x0000, 0xFFFF)]),
];

class ExploreProgress {
  ExploreProgress(this.total);
  final int total;
  int asked = 0;

  /// Items the module has but will not show without a login.
  final locked = <int>[];
  final found = <ExploredItem>[];
  bool stoppedResponding = false;
}

/// Asks a module for each data identifier in [ranges] (read-only, service
/// 0x22) and reports what it answers. Stops when [cancelled] returns true,
/// or when the module stops responding.
///
/// With [extended], the questions are asked in the extended diagnostic
/// session, where VW modules show more (VCDS reads adaptations there). The
/// session only widens what can be read; nothing is written. The module is
/// put back in its normal session at the end.
Stream<ExploreProgress> exploreModule(
  UdsClient uds,
  List<ExploreRange> ranges, {
  bool Function()? cancelled,
  ExploreProgress? resume,
  bool extended = false,
}) async* {
  // Continuing an interrupted sweep: keep what it found and skip what it asked.
  final progress = resume ?? ExploreProgress(ranges.fold(0, (n, r) => n + r.count));
  progress.stoppedResponding = false;
  if (extended) {
    try {
      await uds.diagnosticSessionControl(extendedSession);
    } on NegativeResponseException catch (e) {
      throw CarDiagException('The module would not switch to the deeper mode: ${e.message}');
    }
  }
  try {
    final skip = progress.asked;
    var index = 0;
    var silent = 0;
    for (final range in ranges) {
      for (var did = range.first; did <= range.last; did++, index++) {
        if (index < skip) continue;
        if (cancelled?.call() ?? false) return;
        // Renew the session now and then, in case the module fell back to
        // its normal one (it does after a few seconds without questions).
        if (extended && index > skip && index % 64 == 0) await _renew(uds);
        try {
          progress.found.add(ExploredItem(did, await _read(uds, did, extended)));
          silent = 0;
        } on NegativeResponseException catch (e) {
          silent = 0;
          if (e.nrc == 0x33) progress.locked.add(did);
        } on NoResponseException {
          // A sleeping or disconnected module would make the whole sweep time out.
          if (++silent >= 12) {
            // Continuing later asks the unanswered ones again.
            progress.asked -= silent - 1;
            progress.stoppedResponding = true;
            yield progress;
            return;
          }
        } on ProtocolException {
          silent = 0;
        }
        progress.asked++;
        if (progress.asked % 8 == 0) yield progress;
      }
    }
    yield progress;
  } finally {
    if (extended) {
      try {
        await uds.diagnosticSessionControl(defaultSession);
      } catch (_) {
        // Gone or busy: the module returns to its normal session by itself.
      }
    }
  }
}

Future<Uint8List> _read(UdsClient uds, int did, bool extended) async {
  try {
    return await uds.readDataByIdentifier(did);
  } on NegativeResponseException catch (e) {
    // "Not in this session": the session ran out; renew it and ask again.
    if (!extended || e.nrc != 0x7F) rethrow;
    await _renew(uds);
    return uds.readDataByIdentifier(did);
  }
}

Future<void> _renew(UdsClient uds) async {
  try {
    await uds.diagnosticSessionControl(extendedSession);
  } on NegativeResponseException {
    // Asking keeps going; the answers show what it allows.
  } on NoResponseException {
    // The next question finds out whether the module is still there.
  } on ProtocolException {
    // Same.
  }
}

/// A text file of what a module answered, for sharing.
String exploreResultText({
  required String car,
  required String module,
  required String partNumber,
  required String preset,
  required ExploreProgress progress,
  required DateTime when,
}) {
  final b = StringBuffer()
    ..writeln('Car Diagnostics module explorer')
    ..writeln('Car: $car')
    ..writeln('Module: $module${partNumber.isEmpty ? '' : '   part $partNumber'}')
    ..writeln(
      'Sweep: $preset, ${progress.asked} of ${progress.total} items asked'
      '${progress.stoppedResponding ? ' (module stopped responding)' : ''}',
    )
    ..writeln('When: ${when.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}')
    ..writeln('Answered: ${progress.found.length}   Locked: ${progress.locked.length}')
    ..writeln();
  for (final item in progress.found) {
    final notes = [if (item.text != null) '"${item.text}"', if (item.number != null) '= ${item.number}'];
    b.writeln('${item.id}  ${item.hex}${notes.isEmpty ? '' : '    ${notes.join('  ')}'}');
  }
  if (progress.locked.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Locked (needs a login): '
        '${progress.locked.map((d) => d.toRadixString(16).toUpperCase().padLeft(4, '0')).join(' ')}',
      );
  }
  return b.toString();
}

/// Where the latest explorer results of a module are kept.
String explorerResultPath(String vin, String moduleAddress) =>
    'explorer/${vin.isEmpty ? 'unknown' : vin}/${moduleAddress.isEmpty ? 'module' : moduleAddress}.txt';
