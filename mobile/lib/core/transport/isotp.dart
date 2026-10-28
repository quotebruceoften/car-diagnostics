import 'dart:typed_data';

import '../errors.dart';
import '../hex.dart';

/// Splits a payload into 8-byte CAN frames (ISO 15765-2).
List<Uint8List> segment(List<int> payload, {int pad = 0x00}) {
  Uint8List padded(List<int> f) => Uint8List.fromList([...f, for (var i = f.length; i < 8; i++) pad]);
  if (payload.length <= 7) {
    return [
      padded([payload.length, ...payload]),
    ];
  }
  if (payload.length > 0xFFF) throw ArgumentError('payload too long for ISO-TP');
  final frames = [
    Uint8List.fromList([0x10 | (payload.length >> 8), payload.length & 0xFF, ...payload.sublist(0, 6)]),
  ];
  var seq = 1;
  for (var i = 6; i < payload.length; i += 7) {
    final end = i + 7 < payload.length ? i + 7 : payload.length;
    frames.add(padded([0x20 | (seq & 0x0F), ...payload.sublist(i, end)]));
    seq++;
  }
  return frames;
}

class _Partial {
  _Partial(this.length, this.buffer);
  final int length;
  final List<int> buffer;
  int nextSeq = 1;
}

/// Reassembles raw CAN frames, which may be interleaved between ECUs.
class Reassembler {
  final _partial = <int, _Partial>{};
  final messages = <(int, Uint8List)>[];
  final flowControl = <int, Uint8List>{};

  bool get incomplete => _partial.isNotEmpty;

  void feed(int canId, List<int> frame) {
    if (frame.isEmpty) return;
    switch (frame[0] >> 4) {
      case 0x0:
        final length = frame[0] & 0x0F;
        if (length == 0 || length > frame.length - 1) {
          throw ProtocolException('bad single frame from ${hexId(canId)}: ${bytesToHex(frame)}');
        }
        messages.add((canId, Uint8List.fromList(frame.sublist(1, 1 + length))));
      case 0x1:
        final length = ((frame[0] & 0x0F) << 8) | frame[1];
        _partial[canId] = _Partial(length, [...frame.sublist(2)]);
      case 0x2:
        final p = _partial[canId];
        if (p == null) {
          throw ProtocolException('consecutive frame without first frame from ${hexId(canId)}');
        }
        if ((frame[0] & 0x0F) != (p.nextSeq & 0x0F)) {
          throw ProtocolException('ISO-TP sequence error from ${hexId(canId)}');
        }
        p.buffer.addAll(frame.sublist(1));
        p.nextSeq++;
        if (p.buffer.length >= p.length) {
          _partial.remove(canId);
          messages.add((canId, Uint8List.fromList(p.buffer.sublist(0, p.length))));
        }
      case 0x3:
        flowControl[canId] = Uint8List.fromList(frame.sublist(0, 3));
      default:
        throw ProtocolException('unknown ISO-TP frame from ${hexId(canId)}: ${bytesToHex(frame)}');
    }
  }
}
