import '../core/coding/coder.dart';
import '../core/errors.dart';
import '../core/hex.dart';
import '../core/obd/dtc.dart';
import '../core/uds/uds_client.dart';

/// A diagnosable module (control unit) in a car.
class ModuleDef {
  const ModuleDef({required this.address, required this.name, required this.txId, required this.rxId, this.codingDid});

  /// The brand's own short name for the module, e.g. VW "09".
  final String address;
  final String name;
  final int txId;
  final int rxId;

  /// Overrides [Brand.codingDid] for this module.
  final int? codingDid;

  String get label => address.isEmpty ? name : '$address · $name';

  @override
  String toString() => '$label (${hexId(txId)})';
}

/// Everything make-specific lives behind this interface. To support a new
/// make, implement it in `lib/brands/<make>.dart` and add it to
/// `registry.dart`; the rest of the app works unchanged.
abstract class Brand {
  const Brand();

  /// Stable identifier, also used in coding profiles' "brand" field.
  String get id;
  String get name;

  /// World manufacturer identifiers (first 3 VIN characters).
  List<String> get wmiPrefixes;

  /// Modules to look for during a scan.
  List<ModuleDef> get modules;

  /// Identification data to show for a module, in display order.
  Map<int, String> get identificationDids => const {
    0xF187: 'Part number',
    0xF189: 'Software version',
    0xF191: 'Hardware number',
    0xF197: 'System name',
    0xF18C: 'Serial number',
  };

  int get partNumberDid => 0xF187;

  /// Data identifier that holds a module's coding, if the make has one.
  int? get codingDid => null;

  /// Bundled coding profile assets for this brand.
  List<String> get profileAssets => const [];

  int? codingDidFor(ModuleDef module) => module.codingDid ?? codingDid;

  CodingAccess codingAccessFor(ModuleDef module) => const CodingAccess();

  bool matchesVin(String vin) {
    final v = vin.toUpperCase();
    return wmiPrefixes.any(v.startsWith);
  }

  String describeDtc(Dtc dtc) => describeGenericDtc(dtc.code);

  /// A make-specific hint for an error, shown under the error message.
  String? explainError(CarDiagException error, {bool writing = false}) {
    if (error is NegativeResponseException && writing && (error.nrc == 0x33 || error.nrc == 0x35)) {
      return 'The module needs a security access login before it accepts changes.';
    }
    return null;
  }
}
