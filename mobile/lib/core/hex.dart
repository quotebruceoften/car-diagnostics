import 'dart:typed_data';

/// "1A2B" or "1A 2B" -> bytes.
Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
    throw FormatException('not a hex string: $hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// Bytes -> "1A2B" (or "1A 2B" with [separator] ' ').
String bytesToHex(List<int> bytes, {String separator = ''}) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(separator);

String hexId(int id, [int width = 3]) => '0x${id.toRadixString(16).toUpperCase().padLeft(width, '0')}';

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Shows printable identifiers (part numbers, VINs) as text, anything else as hex.
String formatDidValue(List<int> data) {
  var end = data.length;
  while (end > 0 && (data[end - 1] == 0 || data[end - 1] == 0x20)) {
    end--;
  }
  final trimmed = data.sublist(0, end);
  if (trimmed.isNotEmpty && trimmed.every((b) => b >= 32 && b < 127)) {
    return String.fromCharCodes(trimmed);
  }
  return bytesToHex(data, separator: ' ');
}
