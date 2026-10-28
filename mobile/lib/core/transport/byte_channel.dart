import 'dart:async';
import 'dart:io';

/// A raw, bidirectional byte pipe to an adapter: Bluetooth LE, Wi-Fi (TCP),
/// or the in-app emulator. The ELM327 driver only needs this.
abstract class ByteChannel {
  Stream<List<int>> get incoming;
  Future<void> write(List<int> data);
  Future<void> close();
  String get name;
}

/// Wi-Fi adapters expose the ELM327 on a TCP port (usually 192.168.0.10:35000).
class TcpByteChannel implements ByteChannel {
  TcpByteChannel._(this._socket, this.name);

  final Socket _socket;
  @override
  final String name;

  static Future<TcpByteChannel> connect(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return TcpByteChannel._(socket, '$host:$port');
  }

  @override
  Stream<List<int>> get incoming => _socket;

  @override
  Future<void> write(List<int> data) async {
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<void> close() => _socket.close();
}
