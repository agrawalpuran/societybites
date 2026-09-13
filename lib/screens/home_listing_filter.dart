import '../models/data.dart';
import '../models/food_type.dart';

/// Client-side Home listing filter. Does not fetch; uses already-loaded data.
List<FoodItem> applyHomeListingFilters(
  Iterable<FoodItem> listings, {
  String? category,
  String searchQuery = '',
  String? foodType,
}) {
  var results = listings.where((food) => !food.isPreOrder).toList();

  final selectedType = parseFoodType(foodType);
  if (selectedType != null) {
    results = results.where((food) => food.foodType == selectedType).toList();
  }

  if (category != null && category != 'All') {
    results = results.where((food) => food.category == category).toList();
  }

  if (searchQuery.isNotEmpty) {
    final q = searchQuery.toLowerCase();
    results = results.where((food) {
      return food.name.toLowerCase().contains(q) ||
          food.sellerName.toLowerCase().contains(q) ||
          food.block.toLowerCase().contains(q) ||
          food.tags.any((tag) => tag.toLowerCase().contains(q));
    }).toList();
  }

  return results;
}
