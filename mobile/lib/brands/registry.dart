import 'brand.dart';
import 'generic.dart';
import 'vag.dart';

export 'brand.dart';

/// Every supported make. Add new brands here.
const List<Brand> supportedBrands = [VagBrand()];

const Brand genericBrand = GenericBrand();

/// Picks the brand from the VIN's manufacturer prefix (falls back to generic).
Brand brandForVin(String? vin) {
  if (vin == null || vin.length < 3) return genericBrand;
  for (final b in supportedBrands) {
    if (b.matchesVin(vin)) return b;
  }
  return genericBrand;
}

Brand brandById(String id) =>
    [...supportedBrands, genericBrand].firstWhere((b) => b.id == id, orElse: () => genericBrand);
