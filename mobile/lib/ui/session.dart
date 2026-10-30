import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../brands/registry.dart';
import '../core/alerts.dart';
import '../core/coding/coder.dart';
import '../core/coding/profile.dart';
import '../core/errors.dart';
import '../core/history.dart';
import '../core/obd/dtc.dart';
import '../core/obd/obd_client.dart';
import '../core/obd/pids.dart';
import '../core/reminder_plan.dart';
import '../core/service_log.dart';
import '../core/store.dart';
import '../core/transport/byte_channel.dart';
import '../core/transport/elm327.dart';
import '../core/transport/transport.dart';
import '../core/uds/uds_client.dart';
import '../platform/notifications.dart';
import '../sim/elm_emulator.dart';
import '../sim/vehicle.dart';
import 'car_media.dart';
import 'scan_state.dart';
import 'settings.dart';

/// The connection to one car, shared by every screen.
class DiagSession extends ChangeNotifier {
  DiagSession({
    AppSettings? settings,
    BackupStore? backupStore,
    CarMediaStore? mediaStore,
    HistoryStore? historyStore,
    DataStore? dataStore,
    ReminderNotifier? notifier,
    AssetBundle? assets,
    this.demoLatency = const Duration(milliseconds: 15),
  }) : settings = settings ?? AppSettings(),
       _backupStore = backupStore,
       _mediaStore = mediaStore,
       _historyStore = historyStore,
       _dataStore = dataStore,
       notifier = notifier ?? LocalReminderNotifier(),
       _assets = assets ?? rootBundle {
    scan.onComplete = _saveScan;
    alerts.rules = this.settings.alertRules;
    this.settings.addListener(() => alerts.rules = this.settings.alertRules);
  }

  /// Live-data alerts (e.g. engine too hot), shared by every live screen.
  final alerts = AlertWatcher(onTriggered: (_) => HapticFeedback.heavyImpact());

  /// Feeds a live reading to the alerts.
  void observe(Pid pid, Object value) {
    if (value is num) alerts.report(pid.name, value.toDouble(), range: pid.max - pid.min);
  }

  /// Battery voltage at the OBD port: measured by the adapter when it can
  /// (fast, and works while cranking), otherwise reported by the engine.
  Future<double?> batteryVoltage() async {
    final t = transport;
    if (t is BatteryVoltageReader) return (t as BatteryVoltageReader).batteryVoltage();
    return (await obd.read('module_voltage')).numeric;
  }

  DataStore? _dataStore;

  /// The app's own files (service log, trips, timer results).
  Future<DataStore> dataStore() async {
    final existing = _dataStore;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    return _dataStore = FileDataStore(docs);
  }

  Future<ServiceLog> loadServiceLog(String vin) async =>
      ServiceLog.parse(await (await dataStore()).read(ServiceLog.pathFor(vin)));

  /// Phone notifications for service reminders.
  final ReminderNotifier notifier;

  Future<void> saveServiceLog(String vin, ServiceLog log) async {
    await (await dataStore()).write(ServiceLog.pathFor(vin), log.toJsonString());
    unawaited(syncServiceNotifications(vin, log));
  }

  /// Schedules (or cancels) the notifications for [vin]'s service reminders.
  Future<void> syncServiceNotifications(String vin, [ServiceLog? log]) async {
    if (vin.isEmpty) return;
    if (!settings.serviceNotifications) {
      await notifier.sync(vin, const []);
      return;
    }
    final l = log ?? await loadServiceLog(vin);
    final name = settings.lastCar?.vin == vin ? settings.lastCar!.name : brandForVin(vin).identify(vin).title;
    await notifier.sync(vin, planServiceNotices(vin, name, l, DateTime.now()));
  }

  /// Last odometer reading from the car this session (km), if it reports one.
  double? odometerKm;

  /// Cars from about 2019 report the odometer over OBD; record it in the
  /// service log so reminders by distance stay current.
  Future<void> _syncOdometer() async {
    final v = vin;
    if (v == null) return;
    try {
      final km = (await obd.read('odometer')).numeric;
      if (km == null || !connected || vin != v) return;
      odometerKm = km;
      final log = await loadServiceLog(v);
      log.updateMileage(km.round(), DateTime.now());
      await saveServiceLog(v, log);
      notifyListeners();
    } catch (_) {
      // Most older cars don't report it; the owner types it in instead.
    }
  }

  final AssetBundle _assets;

  /// User preferences (units, theme, remembered adapter).
  final AppSettings settings;

  /// Simulated per-request delay of the demo car, so it feels like a real one.
  final Duration demoLatency;

  /// The simulated car, while connected to the demo.
  Vehicle? demoVehicle;
  BackupStore? _backupStore;
  CarMediaStore? _mediaStore;
  HistoryStore? _historyStore;

  /// The user's photo or video of the connected car, if they added one.
  CarMedia? carMedia;

  Transport? _transport;
  Brand brand = genericBrand;
  String? vin;
  bool busy = false;
  String status = '';
  List<CodingProfile> profiles = const [];

  /// Module scan results, shared by the Modules and Coding tabs.
  final scan = ScanState();

  /// Model and year decoded from the VIN.
  VehicleIdentity get identity => brand.identify(vin);

  bool get connected => _transport != null;
  Transport get transport => _transport ?? (throw CarDiagException('Not connected'));
  ObdClient get obd => ObdClient(transport);
  String get adapterDescription => _transport?.description ?? '';

  Future<CarMediaStore> _media() async {
    final existing = _mediaStore;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    return _mediaStore = CarMediaStore(Directory('${docs.path}/car_media'));
  }

  String get _mediaKey => vin ?? 'unknown';

  /// Loads the car's picture in the background; the card shows a placeholder until then.
  Future<void> _loadCarMedia() async {
    final key = _mediaKey;
    try {
      final media = await (await _media()).get(key);
      if (connected && key == _mediaKey) {
        carMedia = media;
        notifyListeners();
      }
    } catch (_) {
      // No picture is fine.
    }
  }

  /// Stores [sourcePath] (a picked photo or video) as this car's picture.
  Future<void> setCarMedia(CarMediaType type, String sourcePath) async {
    carMedia = await (await _media()).save(_mediaKey, type, sourcePath);
    notifyListeners();
  }

  Future<void> removeCarMedia() async {
    await (await _media()).remove(_mediaKey);
    carMedia = null;
    notifyListeners();
  }

  Future<HistoryStore> historyStore() async {
    final existing = _historyStore;
    if (existing != null) return existing;
    final docs = await getApplicationDocumentsDirectory();
    return _historyStore = FileHistoryStore(Directory('${docs.path}/scan_history'));
  }

  /// The scan record of the last completed scan in this session.
  ScanRecord? lastRecord;

  ScanRecord recordFromScan() => ScanRecord(
    timestamp: scan.finishedAt ?? DateTime.now(),
    vin: vin ?? '',
    carName: identity.title,
    modules: [
      for (final m in scan.present)
        ModuleRecord(
          address: m.def.address,
          name: m.def.name,
          partNumber: m.partNumber,
          faultsReadable: m.dtcs != null,
          faults: [
            for (final d in m.dtcs ?? const <Dtc>[])
              FaultRecord(
                code: d.code,
                display: d.display,
                description: brand.describeDtc(d),
                active: d.status == null ? null : d.active,
              ),
          ],
        ),
    ],
  );

  Future<void> _saveScan() async {
    if (!connected || scan.present.isEmpty) return;
    final record = lastRecord = recordFromScan();
    notifyListeners();
    try {
      await (await historyStore()).save(record);
    } catch (_) {
      // History is a convenience; a failed save must not disturb diagnostics.
    }
  }

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

  /// Set once the app has tried reconnecting to the saved adapter at launch.
  bool autoReconnectTried = false;

  Future<void> connectWifi(String host, int port) =>
      _connect(remember: SavedAdapter.wifi(host: host, port: port), () async {
        _setStatus('Connecting to $host:$port...');
        final channel = await TcpByteChannel.connect(host, port).catchError(
          (Object e) => throw TransportException(
            'Could not reach the adapter at $host:$port. '
            'Is the phone connected to the adapter\'s Wi-Fi network?',
          ),
        );
        return _initAdapter(channel);
      });

  /// Connects through an adapter channel (e.g. Bluetooth); [remember] saves
  /// the adapter for reconnecting next time.
  Future<void> connectChannel(Future<ByteChannel> Function() open, {SavedAdapter? remember}) =>
      _connect(remember: remember, () async {
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

  Future<void> _connect(Future<Transport> Function() open, {SavedAdapter? remember}) async {
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
      if (remember != null) settings.setLastAdapter(remember);
      if (vin case final v? when demoVehicle == null) settings.setLastCar(SavedCar(vin: v, name: identity.title));
      unawaited(_loadCarMedia());
      unawaited(_syncOdometer());
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
    carMedia = null;
    lastRecord = null;
    odometerKm = null;
    alerts.reset();
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

/// Keeps the screen on while driving screens are open.
Future<void> keepScreenOn(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (_) {
    // Not available in tests or on some platforms.
  }
}

class SessionScope extends InheritedNotifier<DiagSession> {
  const SessionScope({super.key, required DiagSession session, required super.child}) : super(notifier: session);

  static DiagSession of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// Access without subscribing to changes (for callbacks).
  static DiagSession read(BuildContext context) => context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
