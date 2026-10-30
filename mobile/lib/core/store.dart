import 'dart:io';

/// Small text files (JSON) kept by the app, addressed by relative paths such
/// as "service_log/WVW....json".
abstract class DataStore {
  Future<String?> read(String path);
  Future<void> write(String path, String content);
  Future<void> delete(String path);

  /// Every file under [dir], as paths relative to the store, sorted.
  Future<List<String>> list(String dir);
}

class MemoryDataStore implements DataStore {
  final files = <String, String>{};

  @override
  Future<String?> read(String path) async => files[path];

  @override
  Future<void> write(String path, String content) async => files[path] = content;

  @override
  Future<void> delete(String path) async => files.remove(path);

  @override
  Future<List<String>> list(String dir) async => files.keys.where((p) => p.startsWith('$dir/')).toList()..sort();
}

class FileDataStore implements DataStore {
  FileDataStore(this.root);
  final Directory root;

  File _file(String path) {
    if (path.split('/').contains('..') || path.startsWith('/')) throw ArgumentError('bad path $path');
    return File('${root.path}/$path');
  }

  @override
  Future<String?> read(String path) async {
    final f = _file(path);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String path, String content) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    // Write then rename, so a crash never leaves half a file.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String path) async {
    final f = _file(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<String>> list(String dir) async {
    final d = Directory('${root.path}/$dir');
    if (!await d.exists()) return [];
    final prefix = '${root.path}/';
    return [
      await for (final e in d.list(recursive: true))
        if (e is File && !e.path.endsWith('.tmp')) e.path.substring(prefix.length),
    ]..sort();
  }
}
