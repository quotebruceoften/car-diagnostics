import 'dart:convert';
import 'dart:typed_data';

import '../errors.dart';

/// Bit-level layout of one coding option. [bit] is the field's least
/// significant bit (0 = LSB); a field must fit inside its byte.
class CodingOption {
  CodingOption({
    required this.key,
    required this.label,
    required this.byte,
    required this.bit,
    required this.width,
    required this.type,
    this.values = const {},
    this.min = 0,
    int? max,
    this.unit = '',
  }) : max = max ?? (1 << width) - 1;

  final String key;
  final String label;
  final int byte;
  final int bit;
  final int width;

  /// 'bool', 'enum' or 'int'.
  final String type;
  final Map<int, String> values;
  final int min;
  final int max;
  final String unit;

  int get mask => ((1 << width) - 1) << bit;

  int raw(List<int> data) => (data[byte] & mask) >> bit;

  String display(List<int> data) {
    final r = raw(data);
    return switch (type) {
      'bool' => r != 0 ? 'on' : 'off',
      'enum' => values[r] ?? 'unknown ($r)',
      _ => unit.isEmpty ? '$r' : '$r $unit',
    };
  }

  /// Raw field values the user can pick from (for bool/enum).
  List<(int, String)> get choices => switch (type) {
    'bool' => const [(0, 'off'), (1, 'on')],
    'enum' => [for (final e in values.entries) (e.key, e.value)],
    _ => const [],
  };

  void validate(int raw) {
    final ok = switch (type) {
      'bool' => raw == 0 || raw == 1,
      'enum' => values.containsKey(raw),
      _ => raw >= min && raw <= max,
    };
    if (!ok) throw CodingException('$label: $raw is not allowed (${describeRange()})');
  }

  /// Parses a user-entered value ("on", "15 km/h", "5") into the raw field value.
  int parse(String text) {
    final t = text.trim().toLowerCase();
    switch (type) {
      case 'bool':
        if (const {'1', 'on', 'true', 'yes'}.contains(t)) return 1;
        if (const {'0', 'off', 'false', 'no'}.contains(t)) return 0;
        throw CodingException('$label: expected on or off');
      case 'enum':
        for (final e in values.entries) {
          if (e.value.toLowerCase() == t) return e.key;
        }
        final n = int.tryParse(t);
        if (n != null && values.containsKey(n)) return n;
        throw CodingException('$label: expected one of ${values.values.join(', ')}');
      default:
        final n = int.tryParse(t);
        if (n == null) throw CodingException('$label: expected a number');
        validate(n);
        return n;
    }
  }

  void apply(List<int> data, int raw) {
    validate(raw);
    data[byte] = (data[byte] & ~mask & 0xFF) | ((raw << bit) & mask);
  }

  String describeRange() => switch (type) {
    'bool' => 'on/off',
    'enum' => values.values.join(' | '),
    _ => '$min..$max${unit.isEmpty ? '' : ' $unit'}',
  };
}

/// Describes how a module's coding block maps to named options.
///
/// Same JSON format as the cardiag command-line tool, plus optional
/// matching fields used by the app: `brand`, `module` (brand-specific address,
/// e.g. VW "09") and `part_numbers` (prefixes of the module's part number).
class CodingProfile {
  CodingProfile({
    required this.id,
    required this.name,
    required this.txId,
    required this.rxId,
    required this.did,
    required this.length,
    required this.options,
    this.session = 0x03,
    this.securityLevel,
    this.securityAlgorithm,
    this.description = '',
    this.brand,
    this.module,
    this.partNumbers = const [],
  });

  final String id;
  final String name;
  final String description;
  final int txId;
  final int rxId;
  final int did;
  final int length;
  final int session;
  final int? securityLevel;
  final String? securityAlgorithm;
  final List<CodingOption> options;
  final String? brand;
  final String? module;
  final List<String> partNumbers;

  CodingOption option(String key) =>
      options.firstWhere((o) => o.key == key, orElse: () => throw CodingException('Profile $id has no option "$key"'));

  /// Whether this profile describes the module with [partNumber].
  bool matches({required String brandId, required String moduleAddress, String? partNumber}) {
    if (brand != null && brand != brandId) return false;
    if (module != null && module!.toUpperCase() != moduleAddress.toUpperCase()) return false;
    if (partNumbers.isEmpty) return true;
    final pn = (partNumber ?? '').replaceAll(' ', '').toUpperCase();
    return partNumbers.any((p) => pn.startsWith(p.replaceAll(' ', '').toUpperCase()));
  }

  Map<String, String> decode(List<int> data) {
    checkLength(data);
    return {for (final o in options) o.key: o.display(data)};
  }

  /// Returns a copy of [data] with the given options changed (raw values).
  Uint8List applyRaw(List<int> data, Map<String, int> changes) {
    checkLength(data);
    final out = Uint8List.fromList(data);
    changes.forEach((key, raw) => option(key).apply(out, raw));
    return out;
  }

  /// Same as [applyRaw] but with user-entered text values.
  Uint8List apply(List<int> data, Map<String, String> changes) =>
      applyRaw(data, {for (final e in changes.entries) e.key: option(e.key).parse(e.value)});

  void checkLength(List<int> data) {
    if (data.length != length) {
      throw CodingException(
        'Coding block is ${data.length} bytes but profile "$name" expects $length - wrong module or profile?',
      );
    }
  }

  /// Accepts JSON ints and strings such as "8" or "0x726".
  static int _int(Object? v) {
    if (v is int) return v;
    final s = '$v'.trim().toLowerCase();
    return s.startsWith('0x') ? int.parse(s.substring(2), radix: 16) : int.parse(s);
  }

  factory CodingProfile.fromJson(Map<String, dynamic> d, {String source = ''}) {
    try {
      final length = _int(d['length']);
      final seen = <String>{};
      final options = <CodingOption>[];
      for (final o in (d['options'] as List).cast<Map<String, dynamic>>()) {
        final type = (o['type'] ?? 'bool') as String;
        final width = _int(o['width'] ?? 1);
        final opt = CodingOption(
          key: o['key'] as String,
          label: (o['label'] ?? o['key']) as String,
          byte: _int(o['byte']),
          bit: _int(o['bit'] ?? 0),
          width: width,
          type: type,
          values: {
            for (final e in ((o['values'] ?? const <String, dynamic>{}) as Map<String, dynamic>).entries)
              _int(e.key): e.value as String,
          },
          min: _int(o['min'] ?? 0),
          max: o['max'] == null ? null : _int(o['max']),
          unit: (o['unit'] ?? '') as String,
        );
        if (!const {'bool', 'enum', 'int'}.contains(type)) throw CodingException('${opt.key}: unknown type $type');
        if (type == 'bool' && width != 1) throw CodingException('${opt.key}: bool options must be 1 bit');
        if (type == 'enum' && opt.values.isEmpty) throw CodingException('${opt.key}: enum options need values');
        if (opt.byte < 0 || opt.byte >= length || opt.bit < 0 || opt.bit + width > 8) {
          throw CodingException('${opt.key}: field does not fit in byte ${opt.byte}');
        }
        if (type == 'int' && !(0 <= opt.min && opt.min <= opt.max && opt.max < (1 << width))) {
          throw CodingException('${opt.key}: min/max do not fit in $width bits');
        }
        if (!seen.add(opt.key)) throw CodingException('duplicate option ${opt.key}');
        options.add(opt);
      }
      final security = d['security'] as Map<String, dynamic>?;
      final txId = _int(d['tx_id']);
      return CodingProfile(
        id: d['id'] as String,
        name: (d['name'] ?? d['id']) as String,
        description: (d['description'] ?? '') as String,
        txId: txId,
        rxId: d['rx_id'] == null ? txId + 8 : _int(d['rx_id']),
        did: _int(d['did']),
        length: length,
        session: _int(d['session'] ?? 3),
        securityLevel: security == null ? null : _int(security['level']),
        securityAlgorithm: security?['algorithm'] as String?,
        options: options,
        brand: d['brand'] as String?,
        module: d['module'] as String?,
        partNumbers: ((d['part_numbers'] ?? const []) as List).cast<String>(),
      );
    } on CodingException catch (e) {
      throw CodingException('Profile $source is invalid: ${e.message}');
    } catch (e) {
      throw CodingException('Profile $source is invalid: $e');
    }
  }

  factory CodingProfile.parse(String json, {String source = ''}) =>
      CodingProfile.fromJson(jsonDecode(json) as Map<String, dynamic>, source: source);
}
