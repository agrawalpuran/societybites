import '../models/data.dart';

/// In-memory cache of variant sibling payloads (same group, sorted on read).
class ListingVariantsCache {
  ListingVariantsCache._();

  static final Map<String, List<Map<String, dynamic>>> _byGroup = {};
  static final Map<String, List<FoodItem>> _foodByGroup = {};
  static final Map<String, String> _listingToGroup = {};

  static String? _groupKey(FoodItem seed) {
    final group = seed.variantGroupId?.trim();
    if (group != null && group.isNotEmpty) return group;
    return null;
  }

  static List<Map<String, dynamic>>? getForSeed(FoodItem seed) {
    final group = _groupKey(seed);
    if (group != null) {
      final hit = _byGroup[group];
      if (hit != null && hit.isNotEmpty) return hit;
    }
    return null;
  }

  /// Sizes already on the device (Home collapses them into one card).
  static List<FoodItem>? foodsForSeed(FoodItem seed) {
    final group = _groupKey(seed);
    if (group == null) return null;
    final hit = _foodByGroup[group];
    if (hit == null || hit.isEmpty) return null;
    return hit;
  }

  static void rememberFoods(List<FoodItem> foods) {
    if (foods.isEmpty) return;
    final group = foods.first.variantGroupId?.trim();
    if (group == null || group.isEmpty) return;
    _foodByGroup[group] = List<FoodItem>.from(foods);
  }

  static void put(FoodItem seed, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return;
    final group = _groupKey(seed);
    if (group != null) {
      _byGroup[group] = rows;
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty) {
          _listingToGroup[id] = group;
        }
      }
      return;
    }
    final id = seed.id.trim();
    if (id.isNotEmpty) {
      _byGroup[id] = rows;
    }
  }
}
