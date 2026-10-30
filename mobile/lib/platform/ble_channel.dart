import 'dart:async';
import 'dart:io';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/errors.dart';
import '../core/transport/byte_channel.dart';

/// Serial-over-GATT services used by Bluetooth LE OBD adapters, as
/// (service, notify characteristic, write characteristic).
final _knownServices = [
  ('fff0', 'fff1', 'fff2'), // Vgate iCar Pro BLE and many clones
  ('ffe0', 'ffe1', 'ffe1'), // HM-10 style modules (most cheap "BLE 4.0" adapters)
  ('18f0', '2af0', '2af1'), // vLinker, OBDLink CX and others
];

const _adapterNameHints = [
  'obd',
  'elm',
  'vgate',
  'vlink',
  'vlinker',
  'icar',
  'obdlink',
  'konnwei',
  'viecar',
  'veepeak',
  'carly',
];

/// Whether a scanned device looks like an OBD adapter (shown first in the list).
bool looksLikeObdAdapter(DiscoveredDevice d) {
  final name = d.name.toLowerCase();
  return _adapterNameHints.any(name.contains) || d.serviceUuids.any((u) => _knownServices.any((k) => _uuidIs(u, k.$1)));
}

bool _uuidIs(Uuid uuid, String short) => uuid.expanded == Uuid.parse(short).expanded;

/// A Bluetooth LE OBD adapter. Works on Android and iOS.
///
/// (Classic Bluetooth adapters do not work on iPhone at all; on Android they
/// would need a separate serial plugin and are not supported yet.)
class BleByteChannel implements ByteChannel {
  BleByteChannel._(this.name, this._connection, this._notify, this._write, this._withResponse) {
    _notifySub = _notify.subscribe().listen(_incoming.add, onError: _incoming.addError);
  }

  static final ble = FlutterReactiveBle();

  @override
  final String name;
  final StreamSubscription<ConnectionStateUpdate> _connection;
  final Characteristic _notify;
  final Characteristic _write;
  final bool _withResponse;
  late final StreamSubscription<List<int>> _notifySub;
  final _incoming = StreamController<List<int>>.broadcast();

  /// Asks for the runtime permissions BLE needs on Android 12+ (iOS asks by itself).
  static Future<void> ensurePermissions() async {
    if (!Platform.isAndroid) return;
    final results = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    if (!results.values.every((s) => s.isGranted)) {
      throw TransportException('Bluetooth permission was denied. Allow it in the system settings.');
    }
    // Android 11 and older also need location to scan (the manifest only
    // declares it up to SDK 30). If it's refused, the scan reports the error.
    await Permission.locationWhenInUse.request();
  }

  static Stream<DiscoveredDevice> scan() async* {
    await ensurePermissions();
    yield* ble.scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency);
  }

  static Future<BleByteChannel> connect(DiscoveredDevice device) => connectTo(device.id, device.name);

  /// Connects to a known adapter by its id (no scan needed), e.g. one saved earlier.
  static Future<BleByteChannel> connectTo(String id, String name) async {
    await ensurePermissions();
    final connected = Completer<void>();
    final connection = ble
        .connectToDevice(id: id, connectionTimeout: const Duration(seconds: 10))
        .listen(
          (update) {
            if (connected.isCompleted) return;
            if (update.connectionState == DeviceConnectionState.connected) connected.complete();
            if (update.connectionState == DeviceConnectionState.disconnected) {
              connected.completeError(TransportException('Could not connect to $name. Is it plugged in?'));
            }
          },
          onError: (Object e) {
            if (!connected.isCompleted) connected.completeError(TransportException('Bluetooth error: $e'));
          },
        );
    try {
      await connected.future.timeout(const Duration(seconds: 15));
      if (Platform.isAndroid) {
        try {
          await ble.requestMtu(deviceId: id, mtu: 247);
        } catch (_) {
          // Optional; we write in small chunks anyway.
        }
      }
      await ble.discoverAllServices(id);
      final services = await ble.getDiscoveredServices(id);
      final (notify, write) = _pickCharacteristics(services);
      final withResponse = !write.isWritableWithoutResponse;
      return BleByteChannel._(name.isEmpty ? id : name, connection, notify, write, withResponse);
    } catch (e) {
      await connection.cancel();
      if (e is CarDiagException) rethrow;
      throw TransportException('Bluetooth error: $e');
    }
  }

  static (Characteristic, Characteristic) _pickCharacteristics(List<Service> services) {
    Characteristic? find(Service s, String uuid) {
      for (final c in s.characteristics) {
        if (_uuidIs(c.id, uuid)) return c;
      }
      return null;
    }

    for (final (svc, notifyId, writeId) in _knownServices) {
      for (final s in services.where((s) => _uuidIs(s.id, svc))) {
        final n = find(s, notifyId);
        final w = find(s, writeId);
        if (n != null && w != null) return (n, w);
      }
    }
    // Unknown adapter: any service with both a notify and a write characteristic.
    for (final s in services) {
      final n = s.characteristics.where((c) => c.isNotifiable || c.isIndicatable).firstOrNull;
      final w = s.characteristics.where((c) => c.isWritableWithoutResponse || c.isWritableWithResponse).firstOrNull;
      if (n != null && w != null) return (n, w);
    }
    throw TransportException('This Bluetooth device does not look like an OBD adapter');
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> write(List<int> data) async {
    // 20 bytes fits the smallest BLE MTU; ELM327 commands are short anyway.
    for (var i = 0; i < data.length; i += 20) {
      await _write.write(data.sublist(i, i + 20 > data.length ? data.length : i + 20), withResponse: _withResponse);
    }
  }

  @override
  Future<void> close() async {
    await _notifySub.cancel();
    await _connection.cancel(); // cancelling the connection stream disconnects
    await _incoming.close();
  }
}
