import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/hex.dart';
import '../core/transport/byte_channel.dart';
import '../core/transport/isotp.dart';
import '../core/transport/transport.dart';
import 'vehicle.dart';

/// Behaves like an ELM327 adapter plugged into a [Vehicle], so the real
/// adapter driver can run without hardware (tests and the "emulated adapter"
/// demo). Implements the subset of the command set the driver uses.
class Elm327Emulator implements ByteChannel {
  Elm327Emulator([Vehicle? vehicle]) : vehicle = vehicle ?? Vehicle.demoGolf() {
    _reset();
  }

  final Vehicle vehicle;
  final int protocol = 6; // ISO 15765-4 CAN 11-bit 500 kbaud
  final log = <String>[];
  final _out = StreamController<List<int>>();
  final _in = StringBuffer();

  late bool _echo, _headers, _spaces, _caf, _connected;
  late int _header;
  int? _rxFilter;
  (int, List<int>, int)? _txPartial;

  void _reset() {
    _echo = true;
    _headers = false;
    _spaces = true;
    _caf = true;
    _connected = false;
    _header = obdBroadcastId;
    _rxFilter = null;
    _txPartial = null;
  }

  @override
  String get name => 'emulated ELM327';

  @override
  Stream<List<int>> get incoming => _out.stream;

  @override
  Future<void> write(List<int> data) async {
    _in.write(ascii.decode(data));
    var text = _in.toString();
    while (text.contains('\r')) {
      final i = text.indexOf('\r');
      final cmd = text.substring(0, i).trim();
      text = text.substring(i + 1);
      _process(cmd);
    }
    _in
      ..clear()
      ..write(text);
  }

  @override
  Future<void> close() => _out.close();

  void _reply(String cmd, List<String> lines) {
    final text = '${_echo ? '$cmd\r' : ''}${lines.map((l) => '$l\r').join()}\r>';
    // Deliver asynchronously and in two chunks, like a real serial link.
    final bytes = ascii.encode(text);
    final half = bytes.length ~/ 2;
    scheduleMicrotask(() {
      _out.add(bytes.sublist(0, half));
      _out.add(bytes.sublist(half));
    });
  }

  void _process(String cmd) {
    log.add(cmd);
    final c = cmd.toUpperCase().replaceAll(' ', '');
    if (c.startsWith('AT')) {
      _reply(cmd, _at(c.substring(2)));
    } else if (c.isNotEmpty && c.length.isEven && RegExp(r'^[0-9A-F]+$').hasMatch(c)) {
      _reply(cmd, _data(hexToBytes(c)));
    } else {
      _reply(cmd, ['?']);
    }
  }

  List<String> _at(String c) {
    switch (c) {
      case 'Z' || 'WS':
        _reset();
        return ['', 'ELM327 v1.5'];
      case 'E0' || 'E1':
        _echo = c == 'E1';
      case 'H0' || 'H1':
        _headers = c == 'H1';
      case 'S0' || 'S1':
        _spaces = c == 'S1';
      case 'CAF0' || 'CAF1':
        _caf = c == 'CAF1';
      case 'AR':
        _rxFilter = null;
      case 'DPN':
        return [_connected ? 'A$protocol' : '0'];
      case 'RV':
        return ['14.2V'];
      default:
        if (c.startsWith('SH')) {
          _header = int.parse(c.substring(2), radix: 16);
        } else if (c.startsWith('CRA')) {
          _rxFilter = int.parse(c.substring(3), radix: 16);
        } else if (!(c.startsWith('L') || c.startsWith('ST') || c.startsWith('SP') || c.startsWith('AT'))) {
          return ['?'];
        }
    }
    return ['OK'];
  }

  String _fmt(int id, List<int> frame) {
    final sep = _spaces ? ' ' : '';
    final body = bytesToHex(frame, separator: sep);
    return _headers ? '${id.toRadixString(16).toUpperCase().padLeft(3, '0')}$sep$body' : body;
  }

  List<String> _data(Uint8List data) {
    final searching = _connected ? <String>[] : ['SEARCHING...'];
    _connected = true;
    List<(int, List<int>)> framed;
    if (_caf) {
      if (data.length > 7) return [...searching, '?'];
      framed = [
        for (final (id, p) in vehicle.handle(_header, data))
          for (final f in segment(p)) (id, f),
      ];
    } else {
      framed = _rawFrame(data);
    }
    final lines = [
      for (final (id, f) in framed)
        if (_rxFilter == null || id == _rxFilter) _fmt(id, f),
    ];
    return [...searching, if (lines.isEmpty) 'NO DATA' else ...lines];
  }

  /// CAN auto formatting off: [frame] is a raw ISO-TP frame. No automatic
  /// flow control is sent, so only the first frame of long replies arrives.
  List<(int, List<int>)> _rawFrame(Uint8List frame) {
    List<(int, List<int>)> firstFrames(List<(int, Uint8List)> replies) => [
      for (final (id, p) in replies) (id, segment(p).first),
    ];
    switch (frame[0] >> 4) {
      case 0x0:
        return firstFrames(vehicle.handle(_header, frame.sublist(1, 1 + (frame[0] & 0x0F))));
      case 0x1:
        final ecu = vehicle.ecu(_header);
        _txPartial = ((((frame[0] & 0x0F) << 8) | frame[1]), [...frame.sublist(2)], 1);
        return ecu == null
            ? []
            : [
                (ecu.rxId, [0x30, 0, 0, 0, 0, 0, 0, 0]),
              ];
      case 0x2:
        final partial = _txPartial;
        if (partial == null) return [];
        final (length, buf, seq) = partial;
        if ((frame[0] & 0x0F) != (seq & 0x0F)) {
          _txPartial = null;
          return [];
        }
        buf.addAll(frame.sublist(1));
        if (buf.length < length) {
          _txPartial = (length, buf, seq + 1);
          return [];
        }
        _txPartial = null;
        return firstFrames(vehicle.handle(_header, buf.sublist(0, length)));
    }
    return [];
  }
}
