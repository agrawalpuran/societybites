import '../models/data.dart';

/// Matches backend [sortSellerCatalogListings] for buyer storefront fallbacks.
int compareFoodItemsByCatalogOrder(FoodItem a, FoodItem b) {
  final ao = a.displayOrder;
  final bo = b.displayOrder;
  final aHas = ao != null;
  final bHas = bo != null;
  if (aHas && bHas && ao != bo) return ao!.compareTo(bo!);
  if (aHas != bHas) return aHas ? -1 : 1;
  final aCreated = a.createdAt?.millisecondsSinceEpoch ?? 0;
  final bCreated = b.createdAt?.millisecondsSinceEpoch ?? 0;
  return bCreated.compareTo(aCreated);
}

List<FoodItem> sortFoodItemsByCatalogOrder(List<FoodItem> items) {
  final copy = List<FoodItem>.from(items);
  copy.sort(compareFoodItemsByCatalogOrder);
  return copy;
}

bool foodItemIsCatalogReorderEligible(FoodItem item) => !item.isPreOrderCatalog;
