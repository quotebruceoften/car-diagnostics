import '../core/coding/coder.dart';
import '../core/errors.dart';
import '../core/hex.dart';
import '../core/obd/dtc.dart';
import '../core/obd/dtc_info.dart';
import '../core/uds/uds_client.dart';
import '../core/vin.dart';

/// Which area of the car a module belongs to (for the car summary).
enum CarZone {
  engine('Engine & gearbox', 'Engine'),
  chassis('Brakes & steering', 'Chassis'),
  interior('Interior & dashboard', 'Interior'),
  body('Lights & body', 'Lights');

  const CarZone(this.label, this.short);
  final String label;
  final String short;
}

/// What the app knows about the connected car from its VIN.
class VehicleIdentity {
  const VehicleIdentity({required this.name, this.year});

  /// e.g. "Volkswagen Golf 7"; the make alone when the model is unknown.
  final String name;
  final int? year;

  String get title => year == null ? name : '$name · $year';
}

/// A diagnosable module (control unit) in a car.
class ModuleDef {
  const ModuleDef({
    required this.address,
    required this.name,
    required this.txId,
    required this.rxId,
    this.codingDid,
    this.zone = CarZone.interior,
  });

  /// The brand's own short name for the module, e.g. VW "09".
  final String address;
  final String name;
  final int txId;
  final int rxId;

  /// Overrides [Brand.codingDid] for this module.
  final int? codingDid;

  /// The area of the car the module belongs to.
  final CarZone zone;

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

  /// Model and year from the VIN. Brands that can decode their
  /// model codes override this; the default only knows the make and year.
  VehicleIdentity identify(String? vin) => VehicleIdentity(name: name, year: vin == null ? null : modelYear(vin));

  bool matchesVin(String vin) {
    final v = vin.toUpperCase();
    return wmiPrefixes.any(v.startsWith);
  }

  String describeDtc(Dtc dtc) {
    final specific = dtcExplanations[dtc.code.toUpperCase()];
    return specific?.title ?? describeGenericDtc(dtc.code);
  }

  /// Make-specific meanings of manufacturer codes, used before the generic table.
  Map<String, DtcInfo> get dtcExplanations => const {};

  /// Plain-language explanation of a fault code on this make.
  DtcInfo explainDtc(String code) => dtcInfo(code, specific: dtcExplanations);

  /// A make-specific hint for an error, shown under the error message.
  String? explainError(CarDiagException error, {bool writing = false}) {
    if (error is NegativeResponseException && writing && (error.nrc == 0x33 || error.nrc == 0x35)) {
      return 'The module needs a security access login before it accepts changes.';
    }
    return null;
  }
}
