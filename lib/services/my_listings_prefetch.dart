import '../models/data.dart';
import 'api_service.dart';
import 'my_listings_cache.dart';
import 'session_service.dart';

/// Shared seller listings fetch for My Listings and dashboard warm-up.
class MyListingsPrefetch {
  static Future<void>? _inFlight;

  static Future<void> warm({
    Future<List<Map<String, dynamic>>> Function()? fetchListings,
  }) {
    return _inFlight ??= _run(fetchListings).whenComplete(() {
      _inFlight = null;
    });
  }

  static Future<void> _run(
    Future<List<Map<String, dynamic>>> Function()? fetchListings,
  ) async {
    List<Map<String, dynamic>> raw;
    if (fetchListings != null) {
      raw = await fetchListings();
    } else {
      final societyId = await SessionService.getSocietyId();
      final userId = await SessionService.getUserId();
      if (userId == null) {
        throw Exception('Please log in again.');
      }
      if (societyId == null || societyId.isEmpty) {
        throw Exception('Join your society to manage listings.');
      }

      raw = await ApiService.getListings(
        societyId: societyId,
        sellerId: userId,
        status: 'all',
        catalogType: 'all',
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw Exception('Could not load listings. Please try again.');
        },
      );
    }

    final listings = <FoodItem>[];
    for (final item in raw) {
      try {
        listings.add(FoodItem.fromJson(item));
      } catch (_) {
        // Skip a corrupt row so one bad listing cannot blank the screen.
      }
    }
    MyListingsCache.replace(listings);
  }
}
