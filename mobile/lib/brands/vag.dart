import '../core/errors.dart';
import '../core/uds/uds_client.dart';
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

  static ModuleDef _m(String address, String name, int txId) =>
      ModuleDef(address: address, name: name, txId: txId, rxId: txId + 0x6A);

  @override
  List<ModuleDef> get modules => [
    const ModuleDef(address: '01', name: 'Engine', txId: 0x7E0, rxId: 0x7E8),
    const ModuleDef(address: '02', name: 'Transmission', txId: 0x7E1, rxId: 0x7E9),
    _m('03', 'Brakes (ABS/ESC)', 0x713),
    _m('08', 'Climate control', 0x746),
    _m('09', 'Central electrics', 0x70E),
    _m('15', 'Airbags', 0x715),
    _m('16', 'Steering wheel electronics', 0x70C),
    _m('17', 'Instrument cluster', 0x714),
    _m('19', 'Gateway', 0x710),
    _m('44', 'Steering assist', 0x712),
    _m('5F', 'Infotainment', 0x773),
  ];

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
