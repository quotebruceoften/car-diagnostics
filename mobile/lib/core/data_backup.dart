import 'dart:convert';

import 'store.dart';

/// Folders under the app's documents directory that hold the user's data.
/// Car photos and videos are left out: they can be large and are easy to
/// add again.
const backupFolders = ['scan_history', 'coding_backups', 'service_log', 'trips', 'performance'];

const _format = 'car-diagnostics-backup';

/// Builds one JSON file with every saved record and the settings.
Future<String> exportData(DataStore store, Map<String, dynamic> settings, {DateTime? now}) async {
  final files = <String, String>{};
  for (final folder in backupFolders) {
    for (final path in await store.list(folder)) {
      final content = await store.read(path);
      if (content != null) files[path] = content;
    }
  }
  return const JsonEncoder.withIndent(' ').convert({
    'format': _format,
    'version': 1,
    'created': (now ?? DateTime.now()).toUtc().toIso8601String(),
    'settings': settings,
    'files': files,
  });
}

class RestoreResult {
  const RestoreResult({required this.added, required this.updated, required this.settings});
  final int added;
  final int updated;

  /// Settings from the backup, for the caller to apply.
  final Map<String, dynamic> settings;
}

/// Restores a backup made by [exportData]. Records that only exist on this
/// phone are kept; files in the backup are added. Service logs are replaced
/// by the backup's copy only when this phone has none.
Future<RestoreResult> importData(DataStore store, String text) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This is not a Car Diagnostics backup file.');
  }
  if (decoded is! Map<String, dynamic> || decoded['format'] != _format || decoded['files'] is! Map) {
    throw const FormatException('This is not a Car Diagnostics backup file.');
  }
  var added = 0, updated = 0;
  for (final e in (decoded['files'] as Map).entries) {
    final path = e.key as String;
    final content = e.value;
    if (content is! String) continue;
    final parts = path.split('/');
    if (!backupFolders.contains(parts.first) || parts.contains('..') || parts.length < 2) continue;
    final existing = await store.read(path);
    if (existing == null) {
      await store.write(path, content);
      added++;
    } else if (existing != content && (parts.first == 'trips' || parts.first == 'performance')) {
      // Lists of results: merge both copies.
      await store.write(path, _mergeLists(existing, content));
      updated++;
    }
  }
  return RestoreResult(
    added: added,
    updated: updated,
    settings: (decoded['settings'] as Map<String, dynamic>?) ?? const {},
  );
}

String _mergeLists(String a, String b) {
  try {
    final seen = <String>{};
    final merged = [
      for (final item in [...jsonDecode(a) as List, ...jsonDecode(b) as List])
        if (seen.add(jsonEncode(item))) item,
    ];
    return jsonEncode(merged);
  } catch (_) {
    return a;
  }
}
