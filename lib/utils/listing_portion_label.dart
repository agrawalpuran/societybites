import '../models/data.dart';
import '../models/listing_discount.dart';

ListingDisplayPrice listingDisplayPrice(FoodItem food) {
  return resolveListingDisplayPrice(
    regularPrice: food.price,
    discountActive: food.discountActive,
    effectivePrice: food.effectivePrice,
    discountPercent: food.discountPercent,
  );
}

double listingBuyerUnitPrice(FoodItem food) {
  return listingDisplayPrice(food).chargedPrice;
}

/// SKU with the lowest charged price. Ties break on regular `price`.
FoodItem cheapestBuyerVariant(List<FoodItem> variants) {
  return variants.reduce((a, b) {
    final byCharged =
        listingBuyerUnitPrice(a).compareTo(listingBuyerUnitPrice(b));
    if (byCharged != 0) return byCharged < 0 ? a : b;
    return a.price <= b.price ? a : b;
  });
}

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

String? portionLabelForFood(FoodItem food) {
  final variant = food.variantLabel?.trim();
  if (variant != null && variant.isNotEmpty) return variant;
  return listingPortionLabel(
    weightValue: food.weightValue,
    weightUnit: food.weightUnit,
  );
}

/// Price line for detail screens, e.g. "₹250 / 250 g" or "₹250 / portion".
String listingPricePerUnitLabel(FoodItem food) {
  final price = '₹${listingBuyerUnitPrice(food).toStringAsFixed(0)}';
  final portion = portionLabelForFood(food);
  if (portion == null) return '$price / portion';
  return '$price / $portion';
}

/// Home / card price. Uses "from ₹X" when sibling sizes have different
/// charged (effective) prices, or when the listing belongs to a size group.
String listingCardPriceLabel(FoodItem food, {List<FoodItem> variants = const []}) {
  if (variants.length > 1) {
    final prices = variants.map(listingBuyerUnitPrice).toList();
    final min = prices.reduce((a, b) => a < b ? a : b);
    final max = prices.reduce((a, b) => a > b ? a : b);
    if ((max - min).abs() > 0.009) {
      return 'from ₹${min.toStringAsFixed(0)}';
    }
  }
  final groupId = food.variantGroupId?.trim();
  if (groupId != null && groupId.isNotEmpty) {
    return 'from ₹${listingBuyerUnitPrice(food).toStringAsFixed(0)}';
  }
  return '₹${listingBuyerUnitPrice(food).toStringAsFixed(0)}';
}

bool listingHasSizeOptions(FoodItem food) {
  if ((food.variantOptionCount ?? 0) > 1) return true;
  final groupId = food.variantGroupId?.trim();
  return groupId != null && groupId.isNotEmpty;
}

/// Blinkit-style subtitle under Add, e.g. "2 options". Null when single SKU.
String? listingOptionsLabel(FoodItem food) {
  final count = food.variantOptionCount ?? 0;
  if (count <= 1) return null;
  return count == 1 ? '1 option' : '$count options';
}
