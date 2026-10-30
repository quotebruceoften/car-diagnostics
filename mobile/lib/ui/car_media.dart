import 'dart:convert';
import 'dart:io';

enum CarMediaType { photo, video }

/// The user's own photo or video of a car.
class CarMedia {
  const CarMedia(this.type, this.file);
  final CarMediaType type;
  final File file;
}

/// Keeps one photo or video per car (keyed by VIN), copied into app storage
/// so it survives the picker's temporary files being cleaned up.
class CarMediaStore {
  CarMediaStore(this.directory);
  final Directory directory;

  File get _index => File('${directory.path}/media.json');

  Future<Map<String, dynamic>> _read() async {
    try {
      return jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {}; // missing or unreadable index: no media yet
    }
  }

  Future<CarMedia?> get(String key) async {
    final entry = (await _read())[key];
    if (entry is! Map<String, dynamic>) return null;
    final file = File('${directory.path}/${entry['file']}');
    final type = CarMediaType.values.asNameMap()[entry['type']];
    if (type == null || !await file.exists()) return null;
    return CarMedia(type, file);
  }

  /// Copies [source] into the store as [key]'s media, replacing any previous one.
  Future<CarMedia> save(String key, CarMediaType type, String source) async {
    await directory.create(recursive: true);
    await remove(key);
    final dot = source.lastIndexOf('.');
    final ext = dot >= 0 && source.length - dot <= 5 ? source.substring(dot).toLowerCase() : '';
    final name = '${_safe(key)}-${DateTime.now().millisecondsSinceEpoch}$ext';
    final file = await File(source).copy('${directory.path}/$name');
    final index = await _read()
      ..[key] = {'type': type.name, 'file': name};
    await _index.writeAsString(jsonEncode(index));
    return CarMedia(type, file);
  }

  Future<void> remove(String key) async {
    final index = await _read();
    final entry = index.remove(key);
    if (entry is Map<String, dynamic>) {
      final old = File('${directory.path}/${entry['file']}');
      if (await old.exists()) await old.delete();
      await _index.writeAsString(jsonEncode(index));
    }
  }

  static String _safe(String key) => key.replaceAll(RegExp('[^A-Za-z0-9]'), '_');
}
