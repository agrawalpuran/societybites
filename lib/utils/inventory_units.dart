/// Shared-pool inventory units. Mass and volume convert to a base; counts stay 1:1.
class InventoryUnit {
  const InventoryUnit({
    required this.apiValue,
    required this.label,
    required this.shortLabel,
    required this.family,
    required this.toBaseFactor,
  });

  final String apiValue;
  final String label;
  final String shortLabel;
  /// mass | volume | count
  final String family;
  /// Multiply entered amount by this to get base units (g, ml, or pieces).
  final int toBaseFactor;

  static const grams = InventoryUnit(
    apiValue: 'grams',
    label: 'Grams (g)',
    shortLabel: 'g',
    family: 'mass',
    toBaseFactor: 1,
  );
  static const kg = InventoryUnit(
    apiValue: 'kg',
    label: 'Kilograms (kg)',
    shortLabel: 'kg',
    family: 'mass',
    toBaseFactor: 1000,
  );
  static const ml = InventoryUnit(
    apiValue: 'ml',
    label: 'Millilitres (ml)',
    shortLabel: 'ml',
    family: 'volume',
    toBaseFactor: 1,
  );
  static const litres = InventoryUnit(
    apiValue: 'litres',
    label: 'Litres (L)',
    shortLabel: 'L',
    family: 'volume',
    toBaseFactor: 1000,
  );
  static const portions = InventoryUnit(
    apiValue: 'portions',
    label: 'Portions / Servings',
    shortLabel: 'portions',
    family: 'count',
    toBaseFactor: 1,
  );
  static const pieces = InventoryUnit(
    apiValue: 'pieces',
    label: 'Pieces',
    shortLabel: 'pcs',
    family: 'count',
    toBaseFactor: 1,
  );
  static const packs = InventoryUnit(
    apiValue: 'packs',
    label: 'Packs',
    shortLabel: 'packs',
    family: 'count',
    toBaseFactor: 1,
  );

  static const all = <InventoryUnit>[
    grams,
    kg,
    ml,
    litres,
    portions,
    pieces,
    packs,
  ];

  static InventoryUnit? tryParse(String? raw) {
    final key = raw?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final unit in all) {
      if (unit.apiValue == key) return unit;
    }
    return null;
  }

  static InventoryUnit parse(String? raw, {InventoryUnit fallback = grams}) {
    return tryParse(raw) ?? fallback;
  }

  /// Convert a human amount in this unit to integer base units (g / ml / count).
  int toBaseUnits(num amount) {
    final scaled = amount * toBaseFactor;
    if (!scaled.isFinite || scaled <= 0) return 0;
    return scaled.round();
  }

  String formatLabel(num amount) {
    final text = amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toString();
    return '$text $shortLabel';
  }
}

/// True when pool and portion can deplete against each other.
bool inventoryUnitsCompatible(InventoryUnit a, InventoryUnit b) =>
    a.family == b.family;
