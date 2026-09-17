import '../models/data.dart';

/// Survives leaving My Listings so the next open is instant.
class MyListingsCache {
  static List<FoodItem> _listings = [];
  static bool _hasSnapshot = false;

  static bool get hasSnapshot => _hasSnapshot;

  static List<FoodItem> get listings => List<FoodItem>.from(_listings);

  static void replace(List<FoodItem> next) {
    _listings = List<FoodItem>.from(next);
    _hasSnapshot = true;
  }

  static void clear() {
    _listings = [];
    _hasSnapshot = false;
  }
}
