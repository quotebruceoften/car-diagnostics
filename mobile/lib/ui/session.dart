import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../brands/registry.dart';
import '../core/coding/coder.dart';
import '../core/coding/profile.dart';
import '../core/errors.dart';
import '../core/obd/obd_client.dart';
import '../core/transport/byte_channel.dart';
import '../core/transport/elm327.dart';
import '../core/transport/transport.dart';
import '../core/uds/uds_client.dart';
import '../sim/elm_emulator.dart';
import '../sim/vehicle.dart';
import 'scan_state.dart';

/// The connection to one car, shared by every screen.
class DiagSession extends ChangeNotifier {
  DiagSession({BackupStore? backupStore, AssetBundle? assets, this.demoLatency = const Duration(milliseconds: 15)})
    : _backupStore = backupStore,
      _assets = assets ?? rootBundle;

  final AssetBundle _assets;

  /// Simulated per-request delay of the demo car, so it feels like a real one.
  final Duration demoLatency;

  /// The simulated car, while connected to the demo.
  Vehicle? demoVehicle;
  BackupStore? _backupStore;

  Transport? _transport;
  Brand brand = genericBrand;
  String? vin;
  bool busy = false;
  String status = '';
  List<CodingProfile> profiles = const [];

  /// Module scan results, shared by the Modules and Coding tabs.
  final scan = ScanState();

  bool get connected => _transport != null;
  Transport get transport => _transport ?? (throw CarDiagException('Not connected'));
  ObdClient get obd => ObdClient(transport);
  String get adapterDescription => _transport?.description ?? '';

  Future<BackupStore> backupStore() async {
    final existing = _backupStore;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    return _backupStore = FileBackupStore(Directory('${docs.path}/coding_backups'));
  }

  /// Connects to the built-in simulated car (no adapter needed).
  Future<void> connectDemo({bool throughEmulatedAdapter = false}) => _connect(() async {
    final vehicle = demoVehicle = Vehicle.demoGolf();
    if (!throughEmulatedAdapter) return SimulatorTransport(vehicle, demoLatency);
    final elm = Elm327Transport(Elm327Emulator(vehicle));
    await elm.initialize();
    return elm;
  });

  Future<void> connectWifi(String host, int port) => _connect(() async {
    _setStatus('Connecting to $host:$port...');
    final channel = await TcpByteChannel.connect(host, port).catchError(
      (Object e) => throw TransportException(
        'Could not reach the adapter at $host:$port. '
        'Is the phone connected to the adapter\'s Wi-Fi network?',
      ),
    );
    return _initAdapter(channel);
  });

  /// Connects through an already opened adapter channel (e.g. Bluetooth).
  Future<void> connectChannel(Future<ByteChannel> Function() open) => _connect(() async {
    _setStatus('Connecting to adapter...');
    return _initAdapter(await open());
  });

  Future<Transport> _initAdapter(ByteChannel channel) async {
    final elm = Elm327Transport(channel);
    try {
      _setStatus('Talking to the car...');
      await elm.initialize();
      return elm;
    } catch (_) {
      await elm.close();
      rethrow;
    }
  }

  Future<void> _connect(Future<Transport> Function() open) async {
    await disconnect();
    busy = true;
    notifyListeners();
    Transport? t;
    try {
      t = await open();
      _setStatus('Reading vehicle identification...');
      vin = await _readVin(t);
      brand = brandForVin(vin);
      await _loadProfiles();
      // Only now do the screens switch over to the connected car.
      _transport = t;
    } catch (e) {
      await t?.close();
      vin = null;
      demoVehicle = null;
      brand = genericBrand;
      rethrow;
    } finally {
      busy = false;
      status = '';
      notifyListeners();
    }
  }

  Future<String?> _readVin(Transport t) async {
    try {
      final v = await ObdClient(t).vin();
      if (v.length == 17) return v;
    } on CarDiagException {
      // Some cars only report the VIN over UDS.
    }
    try {
      final raw = await UdsClient(t, 0x7E0).readDataByIdentifier(0xF190);
      return String.fromCharCodes(raw.where((b) => b >= 0x20 && b < 0x7F)).trim();
    } on CarDiagException {
      return null;
    }
  }

  /// Lets the user pick the make when the VIN doesn't tell us.
  Future<void> setBrand(Brand b) async {
    brand = b;
    scan.reset();
    await _loadProfiles();
    notifyListeners();
  }

  Future<void> _loadProfiles() async {
    profiles = [
      for (final asset in brand.profileAssets)
        CodingProfile.parse(await _assets.loadString(asset, cache: false), source: asset),
    ];
  }

  CodingProfile? profileFor(String moduleAddress, String? partNumber) {
    for (final p in profiles) {
      if (p.matches(brandId: brand.id, moduleAddress: moduleAddress, partNumber: partNumber)) return p;
    }
    return null;
  }

  Future<void> disconnect() async {
    final t = _transport;
    _transport = null;
    vin = null;
    demoVehicle = null;
    scan.reset();
    brand = genericBrand;
    profiles = const [];
    await t?.close();
    notifyListeners();
  }

  void _setStatus(String s) {
    status = s;
    notifyListeners();
  }
}

class SessionScope extends InheritedNotifier<DiagSession> {
  const SessionScope({super.key, required DiagSession session, required super.child}) : super(notifier: session);

  static DiagSession of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// Access without subscribing to changes (for callbacks).
  static DiagSession read(BuildContext context) => context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
