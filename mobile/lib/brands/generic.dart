import 'brand.dart';

/// Fallback for makes without a dedicated brand: the two modules every
/// OBD-II car exposes at standard addresses.
class GenericBrand extends Brand {
  const GenericBrand();

  @override
  String get id => 'generic';

  @override
  String get name => 'Generic OBD-II';

  @override
  List<String> get wmiPrefixes => const [];

  @override
  List<ModuleDef> get modules => const [
    ModuleDef(address: '', name: 'Engine', txId: 0x7E0, rxId: 0x7E8),
    ModuleDef(address: '', name: 'Transmission', txId: 0x7E1, rxId: 0x7E9),
  ];
}
