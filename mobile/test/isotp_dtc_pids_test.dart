import 'package:cardiag_mobile/core/errors.dart';
import 'package:cardiag_mobile/core/obd/dtc.dart';
import 'package:cardiag_mobile/core/obd/pids.dart';
import 'package:cardiag_mobile/core/transport/isotp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final length in [1, 7, 8, 13, 20, 100]) {
    test('ISO-TP round trip, $length bytes', () {
      final payload = List.generate(length, (i) => i & 0xFF);
      final frames = segment(payload);
      expect(frames.every((f) => f.length == 8), isTrue);
      final r = Reassembler();
      for (final f in frames) {
        r.feed(0x7E8, f);
      }
      expect(r.messages.single.$2, payload);
      expect(r.incomplete, isFalse);
    });
  }

  test('reassembles interleaved replies from two ECUs', () {
    final a = List.generate(20, (i) => i), b = List.generate(15, (i) => 100 + i);
    final fa = segment(a), fb = segment(b);
    final r = Reassembler();
    for (var i = 0; i < fa.length; i++) {
      r.feed(0x7E8, fa[i]);
      if (i < fb.length) r.feed(0x7E9, fb[i]);
    }
    expect({for (final (id, d) in r.messages) id: d}, {0x7E8: a, 0x7E9: b});
  });

  test('detects ISO-TP sequence errors', () {
    final frames = segment(List.filled(20, 0));
    final r = Reassembler()..feed(0x7E8, frames[0]);
    expect(() => r.feed(0x7E8, frames[2]), throwsA(isA<ProtocolException>()));
  });

  test('DTC encode/decode round trip', () {
    for (final code in ['P0301', 'P0420', 'C0035', 'B1000', 'U0155', 'P2AF1', 'U3FFF']) {
      expect(decodeDtc(encodeDtc(code)), code);
    }
    expect(decodeDtc([0x01, 0x33]), 'P0133');
    expect(decodeDtc([0xC1, 0x55]), 'U0155');
  });

  test('OBD DTC list skips padding', () {
    expect(parseObdDtcs([2, 0x03, 0x01, 0x04, 0x20, 0, 0]).map((d) => d.code), ['P0301', 'P0420']);
  });

  test('DTC status flags', () {
    const d = Dtc('P0301', status: 0x2B, failureType: 0x1F);
    expect(d.display, 'P0301-1F');
    expect(d.active, isTrue);
    expect(d.statusFlags, containsAll(['confirmed', 'test failed']));
    expect(describeGenericDtc('P1234'), contains('manufacturer specific'));
  });

  test('PID decoding', () {
    expect(lookupPid('rpm').decode([0x1A, 0xF8]), 1726.0);
    expect(lookupPid(0x05).decode([0x7B]), 83);
    expect(lookupPid(0x06).decode([0x80]), 0.0);
    expect(() => lookupPid('nope'), throwsA(isA<CarDiagException>()));
    expect(decodeSupported(0, [0xBE, 0x1F, 0xA8, 0x13]), {
      0x01,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x0C,
      0x0D,
      0x0E,
      0x0F,
      0x10,
      0x11,
      0x13,
      0x15,
      0x1C,
      0x1F,
      0x20,
    });
  });
}
