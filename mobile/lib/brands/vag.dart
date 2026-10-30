import '../core/errors.dart';
import '../core/uds/uds_client.dart';
import '../core/vin.dart';
import 'brand.dart';

/// Volkswagen Group: VW, Audi, Škoda, SEAT, Cupra.
///
/// Module addresses are those commonly used on UDS-based (MQB-era, roughly
/// 2013+) cars, where a module's response ID is its request ID + 0x6A.
/// Not every car has every module; the scan reports which ones answer.
class VagBrand extends Brand {
  const VagBrand();

  @override
  String get id => 'vag';

  @override
  String get name => 'Volkswagen Group';

  @override
  List<String> get wmiPrefixes => const [
    'WVW', 'WV1', 'WV2', 'WVG', '1VW', '3VW', '9BW', '8AW', 'AAV', // Volkswagen
    'WAU', 'WA1', 'WUA', 'TRU', // Audi
    'TMB', 'TMP', // Škoda
    'VSS', // SEAT / Cupra
  ];

  static ModuleDef _m(String address, String name, int txId, CarZone zone) =>
      ModuleDef(address: address, name: name, txId: txId, rxId: txId + 0x6A, zone: zone);

  @override
  List<ModuleDef> get modules => [
    const ModuleDef(address: '01', name: 'Engine', txId: 0x7E0, rxId: 0x7E8, zone: CarZone.engine),
    const ModuleDef(address: '02', name: 'Transmission', txId: 0x7E1, rxId: 0x7E9, zone: CarZone.engine),
    _m('03', 'Brakes (ABS/ESC)', 0x713, CarZone.chassis),
    _m('08', 'Climate control', 0x746, CarZone.interior),
    _m('09', 'Central electrics', 0x70E, CarZone.body),
    _m('15', 'Airbags', 0x715, CarZone.interior),
    _m('16', 'Steering wheel electronics', 0x70C, CarZone.interior),
    _m('17', 'Instrument cluster', 0x714, CarZone.interior),
    _m('19', 'Gateway', 0x710, CarZone.interior),
    _m('44', 'Steering assist', 0x712, CarZone.chassis),
    _m('5F', 'Infotainment', 0x773, CarZone.interior),
  ];

  static const _makes = {
    'WVW': 'Volkswagen', 'WV1': 'Volkswagen', 'WV2': 'Volkswagen', 'WVG': 'Volkswagen', //
    '1VW': 'Volkswagen', '3VW': 'Volkswagen', '9BW': 'Volkswagen', '8AW': 'Volkswagen', 'AAV': 'Volkswagen',
    'WAU': 'Audi', 'WA1': 'Audi', 'WUA': 'Audi', 'TRU': 'Audi',
    'TMB': 'Škoda', 'TMP': 'Škoda',
    'VSS': 'SEAT',
  };

  /// Model codes in VIN positions 7-8, per make.
  static const _models = {
    'Volkswagen': {
      'AU': 'Golf 7',
      'CD': 'Golf 8',
      '1K': 'Golf 5/6',
      '6R': 'Polo',
      'AW': 'Polo',
      '3C': 'Passat',
      '3G': 'Passat',
      '5N': 'Tiguan',
      'AD': 'Tiguan',
      '7P': 'Touareg',
    },
    'Audi': {'8V': 'A3', '8K': 'A4', '8W': 'A4', '4G': 'A6'},
    'Škoda': {'5E': 'Octavia'},
    'SEAT': {'5F': 'Leon'},
  };

  @override
  VehicleIdentity identify(String? vin) {
    if (vin == null || vin.length != 17) return VehicleIdentity(name: name);
    final make = _makes[vin.substring(0, 3).toUpperCase()] ?? 'Volkswagen';
    final model = _models[make]?[vin.substring(6, 8).toUpperCase()];
    return VehicleIdentity(name: model == null ? make : '$make $model', year: modelYear(vin));
  }

  @override
  Map<int, String> get identificationDids => const {
    0xF187: 'Part number',
    0xF189: 'Software version',
    0xF191: 'Hardware number',
    0xF1A3: 'Hardware version',
    0xF197: 'System name',
    0xF18C: 'Serial number',
    0xF19E: 'ODX dataset',
    0xF1A2: 'ODX version',
  };

  /// VW stores a module's "long coding" in DID 0x0600.
  @override
  int get codingDid => 0x0600;

  @override
  List<String> get profileAssets => const ['assets/profiles/vag_09_demo.json'];

  @override
  String? explainError(CarDiagException error, {bool writing = false}) {
    if (error is NegativeResponseException && writing && const {0x22, 0x33, 0x35}.contains(error.nrc)) {
      return 'The module refused the change. On 2020+ VW Group cars (e.g. Golf 8, ID. models) many '
          'modules are protected by SFD and must be unlocked online through VW before they accept coding. '
          'Some older modules need a security access login code first.';
    }
    return super.explainError(error, writing: writing);
  }
}
