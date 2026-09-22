import '../models/data.dart';
import '../models/food_type.dart';
import '../models/listing_categories.dart';

/// Restricts listings to an exact VEG / NON_VEG match.
/// `null` foodType (All) returns the input unchanged, including unclassified items.
List<FoodItem> listingsMatchingFoodType(
  Iterable<FoodItem> listings, {
  String? foodType,
}) {
  final selectedType = parseFoodType(foodType);
  if (selectedType == null) return List<FoodItem>.from(listings);
  return listings.where((food) => food.foodType == selectedType).toList();
}

/// Client-side Home listing filter. Does not fetch; uses already-loaded data.
List<FoodItem> applyHomeListingFilters(
  Iterable<FoodItem> listings, {
  String? category,
  String searchQuery = '',
  String? foodType,
}) {
  var results = listings
      .where((food) => !food.isPreOrder && !food.isPreOrderCatalog)
      .toList();
  results = listingsMatchingFoodType(results, foodType: foodType);

  if (category != null && category != 'All') {
    results = results
        .where(
          (food) => listingMatchesHomeCategory(
            food.listingCategories,
            selectedCategory: category,
            legacyCategory: food.category,
          ),
        )
        .toList();
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

  results.sort((a, b) {
    final aRank = a.canAddToCart ? 0 : 1;
    final bRank = b.canAddToCart ? 0 : 1;
    return aRank.compareTo(bRank);
  });

  return results;
}
