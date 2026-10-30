import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../errors.dart';
import '../hex.dart';
import 'byte_channel.dart';
import 'isotp.dart';
import 'transport.dart';

const _fatalReplies = [
  'UNABLE TO CONNECT',
  'CAN ERROR',
  'BUS ERROR',
  'BUS INIT',
  'FB ERROR',
  'DATA ERROR',
  '<DATA ERROR',
  '<RX ERROR',
  'BUFFER FULL',
  'LV RESET',
  'ACT ALERT',
  'STOPPED',
  'ERR',
];

/// ELM327 "AT DPN" protocol number -> CAN identifier length in hex digits.
const _canProtocols = {6: 3, 7: 8, 8: 3, 9: 8};

/// Diagnostic transport over an ELM327-compatible adapter.
///
/// Only CAN protocols (ISO 15765-4) are supported. The adapter runs with
/// headers on and ISO-TP is reassembled here, so replies from several ECUs to
/// one broadcast can be told apart.
class Elm327Transport implements Transport, BatteryVoltageReader {
  Elm327Transport(this.channel, {this.timeout = const Duration(seconds: 5), int responseTimeoutMs = 500})
    : _st = (responseTimeoutMs ~/ 4).clamp(1, 0xFF) {
    _sub = channel.incoming.listen(_onData, onError: _onError, onDone: () => _onError('adapter disconnected'));
  }

  final ByteChannel channel;
  final Duration timeout;
  final int _st;
  final _lock = AsyncLock();
  late final StreamSubscription<List<int>> _sub;
  final _buffer = BytesBuilder();
  Completer<String>? _pending;

  String version = '';
  int? protocolNumber;
  int _idLen = 3;
  int? _txId;
  int? _rxId = -1; // -1: filter state unknown

  @override
  String get description => '${version.isEmpty ? 'ELM327' : version} via ${channel.name}';

  /// Resets the adapter, configures it and detects the vehicle protocol.
  Future<void> initialize({String protocol = '0'}) => _lock.run(() async {
    final List<String> lines;
    try {
      lines = await _command('ATZ', timeout: const Duration(seconds: 5));
    } on TransportException {
      throw TransportException(
        'The adapter connected but does not respond like an ELM327. Some brand-locked adapters '
        "(for example Carly's own scanners) only work with their maker's app.",
      );
    }
    version = lines.firstWhere((l) => l.toUpperCase().contains('ELM'), orElse: () => lines.isEmpty ? '' : lines.last);
    for (final cmd in ['ATE0', 'ATL0', 'ATS0', 'ATH1', 'ATCAF1', 'ATST${_hex2(_st)}', 'ATSP$protocol']) {
      await _expectOk(cmd);
    }
    // Any OBD request makes the adapter search for and lock onto the protocol.
    final probe = await _command('0100', timeout: const Duration(seconds: 15));
    if (probe.any((l) => l.startsWith('UNABLE TO CONNECT'))) {
      throw NoResponseException('Adapter could not reach the car. Is the ignition on?');
    }
    final dpn = (await _command('ATDPN')).last.toUpperCase().replaceFirst('A', '');
    protocolNumber = int.tryParse(dpn, radix: 16);
    if (protocolNumber == null) throw TransportException('unexpected AT DPN reply: $dpn');
    final len = _canProtocols[protocolNumber];
    if (len == null) {
      throw TransportException('This car uses OBD protocol $protocolNumber; only CAN (6-9) is supported.');
    }
    _idLen = len;
    _txId = null;
    _rxId = -1;
  });

  /// Reads the adapter's measurement of battery voltage (AT RV).
  @override
  Future<double?> batteryVoltage() => _lock.run(() async {
    final reply = (await _command('ATRV')).last.replaceAll(RegExp('[^0-9.]'), '');
    return double.tryParse(reply);
  });

  @override
  Future<void> close() async {
    await _sub.cancel();
    await channel.close();
  }

  // ------------------------------------------------------------- low level
  void _onData(List<int> data) {
    _buffer.add(data);
    final pending = _pending;
    if (pending != null && data.contains(0x3E /* > */)) {
      final text = latin1.decode(_buffer.takeBytes());
      _pending = null;
      pending.complete(text.substring(0, text.lastIndexOf('>')));
    }
  }

  void _onError(Object error) {
    final pending = _pending;
    _pending = null;
    pending?.completeError(TransportException('$error'));
  }

  Future<List<String>> _command(String cmd, {Duration? timeout}) async {
    _buffer.clear();
    final completer = _pending = Completer<String>();
    await channel.write(ascii.encode('$cmd\r'));
    final String text;
    try {
      text = await completer.future.timeout(timeout ?? this.timeout);
    } on TimeoutException {
      _pending = null;
      throw TransportException('Adapter did not answer "$cmd" in time');
    }
    final compactCmd = cmd.replaceAll(' ', '');
    return text
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.replaceAll(' ', '') != compactCmd)
        .toList();
  }

  Future<void> _expectOk(String cmd) async {
    final lines = await _command(cmd);
    if (lines.isEmpty || lines.last.toUpperCase() != 'OK') {
      throw TransportException('Adapter rejected $cmd: $lines');
    }
  }

  static String _hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');

  String _idHex(int id) => id.toRadixString(16).toUpperCase().padLeft(_idLen, '0');

  Future<void> _setIds(int txId, int? rxId) async {
    if (txId != _txId) {
      if (_idLen == 3) {
        await _expectOk('ATSH${_idHex(txId)}');
      } else {
        await _expectOk('ATCP${_hex2((txId >> 24) & 0x1F)}');
        await _expectOk('ATSH${(txId & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}');
      }
      _txId = txId;
    }
    if (rxId != _rxId) {
      await _expectOk(rxId == null ? 'ATAR' : 'ATCRA${_idHex(rxId)}');
      _rxId = rxId;
    }
  }

  void _parseInto(List<String> lines, Reassembler reasm) {
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper == 'NO DATA' || upper == 'OK' || upper.startsWith('SEARCHING')) continue;
      if (upper == '?') throw TransportException('Adapter did not understand the request');
      if (_fatalReplies.any(upper.startsWith)) throw TransportException('Adapter reported: $line');
      final compact = upper.replaceAll(' ', '');
      if (!RegExp(r'^[0-9A-F]+$').hasMatch(compact) || compact.length <= _idLen) {
        throw ProtocolException('Unexpected adapter output: "$line"');
      }
      final body = compact.substring(_idLen);
      if (body.length.isOdd) throw ProtocolException('Odd-length frame: "$line"');
      reasm.feed(int.parse(compact.substring(0, _idLen), radix: 16), hexToBytes(body));
    }
  }

  // ------------------------------------------------------------- transport
  @override
  Future<List<Message>> send(int txId, List<int> payload, {int? rxId}) => _lock.run(() async {
    if (payload.isEmpty) throw ArgumentError('empty payload');
    await _setIds(txId, rxId);
    final reasm = Reassembler();
    if (payload.length <= 7) {
      _parseInto(await _command(bytesToHex(payload)), reasm);
    } else {
      if (rxId == null) throw ArgumentError('multi-frame requests need a physical rxId');
      await _sendMultiFrame(payload, rxId, reasm);
    }
    return [for (final (id, data) in reasm.messages) Message(id, data)];
  });

  /// Plain ELM327 chips cannot segment outgoing messages, so long requests
  /// (most coding writes) are sent frame by frame with CAN auto formatting off.
  /// The ECU's reply must fit one frame, which holds for writes.
  Future<void> _sendMultiFrame(List<int> payload, int rxId, Reassembler reasm) async {
    final frames = segment(payload);
    await _expectOk('ATCAF0');
    try {
      var fc = _readFlowControl(await _command(bytesToHex(frames[0])), rxId, reasm);
      if (fc == null) return;
      var (blockSize, stMin) = fc;
      var sentInBlock = 0;
      for (var i = 1; i < frames.length; i++) {
        final last = i == frames.length - 1;
        final blockEnd = blockSize > 0 && sentInBlock + 1 == blockSize && !last;
        final List<String> lines;
        if (last || blockEnd) {
          lines = await _command(bytesToHex(frames[i]));
        } else {
          // No reply is expected, so keep the adapter's wait short.
          await _expectOk('ATST02');
          try {
            lines = await _command(bytesToHex(frames[i]));
          } finally {
            await _expectOk('ATST${_hex2(_st)}');
          }
        }
        if (stMin > 0) await Future<void>.delayed(Duration(milliseconds: stMin));
        if (blockEnd) {
          fc = _readFlowControl(lines, rxId, reasm);
          if (fc == null) return;
          (blockSize, stMin) = fc;
          sentInBlock = 0;
        } else {
          sentInBlock++;
          _parseInto(lines, reasm);
        }
      }
      if (reasm.incomplete) {
        throw ProtocolException('ECU sent a multi-frame reply, which ELM327 cannot receive in this mode');
      }
    } finally {
      await _expectOk('ATCAF1');
    }
  }

  /// Returns (block size, STmin ms), or null if the ECU answered instead.
  (int, int)? _readFlowControl(List<String> lines, int rxId, Reassembler reasm) {
    reasm.flowControl.remove(rxId);
    _parseInto(lines, reasm);
    final fc = reasm.flowControl[rxId];
    if (fc == null) {
      if (reasm.messages.isNotEmpty) return null; // e.g. 7F 2E 13
      throw NoResponseException('ECU did not send ISO-TP flow control');
    }
    if (fc[0] == 0x32) throw ProtocolException('ECU reported ISO-TP overflow (request too long)');
    if (fc[0] != 0x30) throw ProtocolException('Unsupported flow control ${bytesToHex(fc)}');
    return (fc[1], fc[2] <= 0x7F ? fc[2] : 1);
  }
}
