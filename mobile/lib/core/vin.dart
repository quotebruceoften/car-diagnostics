/// Vehicle identification number helpers (ISO 3779).
library;

const _yearCodes = 'ABCDEFGHJKLMNPRSTVWXY123456789';

/// Model year from VIN position 10. The code repeats every 30 years, so
/// this picks the most recent year that isn't in the future.
int? modelYear(String vin, {int? currentYear}) {
  if (vin.length != 17) return null;
  final i = _yearCodes.indexOf(vin[9].toUpperCase());
  if (i < 0) return null;
  final latest = (currentYear ?? DateTime.now().year) + 1; // model years run ahead
  var year = 2010 + i;
  while (year > latest) {
    year -= 30;
  }
  return year;
}
