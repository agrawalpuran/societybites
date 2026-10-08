import '../models/data.dart';

/// Human-readable portion / pack size from listing weight fields.
String? listingPortionLabel({String? weightValue, String? weightUnit}) {
  final value = weightValue?.trim();
  if (value == null || value.isEmpty) return null;

  switch ((weightUnit ?? 'portions').toLowerCase()) {
    case 'grams':
    case 'g':
      return '$value g';
    case 'kg':
    case 'kilograms':
      return '$value kg';
    case 'ml':
      return '$value ml';
    case 'litres':
    case 'l':
      return '$value L';
    case 'portions':
      return value == '1' ? '1 portion' : '$value portions';
    default:
      final unit = weightUnit?.trim();
      if (unit == null || unit.isEmpty) return value;
      return '$value $unit';
  }
}

String? portionLabelForFood(FoodItem food) =>
    listingPortionLabel(weightValue: food.weightValue, weightUnit: food.weightUnit);

/// Price line for detail screens, e.g. "₹250 / 250 g" or "₹250 / portion".
String listingPricePerUnitLabel(FoodItem food) {
  final price = '₹${food.price.toStringAsFixed(0)}';
  final portion = portionLabelForFood(food);
  if (portion == null) return '$price / portion';
  return '$price / $portion';
}
