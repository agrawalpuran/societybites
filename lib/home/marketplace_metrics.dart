import '../models/data.dart';
import '../models/selling_reach.dart';
import '../screens/home_listing_filter.dart';
import 'marketplace_home_state.dart';

/// Own-society maturity, plus nearby dishes the buyer can already see.
class BuyerMarketplaceSnapshot {
  const BuyerMarketplaceSnapshot({
    required this.ownSociety,
    required this.nearbyListings,
    this.neighbourhoodRadiusKm,
    this.neighbourHasListed = false,
  });

  final MarketplaceMetrics ownSociety;
  final List<FoodItem> nearbyListings;

  /// City reach cap, in kilometres. Null when the city has no reach config.
  final double? neighbourhoodRadiusKm;

  /// A dish from this society is in the loaded feed, even if it cannot be ordered.
  final bool neighbourHasListed;
}

/// True when this society's feed already contains a regular dish.
bool societyHasListedDish(
  Iterable<FoodItem> listings, {
  required String? buyerSocietyId,
}) {
  final societyId = buyerSocietyId?.trim();
  for (final food in listings) {
    if (food.isPreOrder || food.isPreOrderCatalog) continue;
    final listedSociety = food.societyId?.trim();
    if (societyId != null &&
        societyId.isNotEmpty &&
        listedSociety != null &&
        listedSociety.isNotEmpty &&
        listedSociety != societyId) {
      continue;
    }
    return true;
  }
  return false;
}

bool _eligibleHomeListing(FoodItem food) {
  return food.isEligibleForHomeFeed &&
      !food.isPreOrder &&
      !food.isPreOrderCatalog &&
      !food.blockedBySellerFssai;
}

/// Own-society counts ignore nearby dishes. Nearby dishes are the ones the
/// existing reach rules already place outside the buyer's society.
BuyerMarketplaceSnapshot buyerMarketplaceSnapshot(
  Iterable<FoodItem> listings, {
  required String? buyerSocietyId,
  required SellingReach cityReach,
}) {
  final choice = effectiveBuyerDistance(null, cityReach);
  final visible = listingsMatchingBuyerDistance(
    listings.where(_eligibleHomeListing),
    choice: choice,
    buyerSocietyId: buyerSocietyId,
    nearbyRadiusKm: cityReach.nearbyRadiusKm,
  );
  final own = <FoodItem>[];
  final nearby = <FoodItem>[];
  for (final food in visible) {
    final reach = homeListingReachFor(
      food,
      buyerSocietyId: buyerSocietyId,
      nearbyRadiusKm: cityReach.nearbyRadiusKm,
    );
    if (reach == HomeListingReach.inSociety) {
      own.add(food);
    } else if (reach == HomeListingReach.beyondSociety) {
      nearby.add(food);
    }
  }
  final sellers = <String>{};
  for (final food in own) {
    final sellerId = food.sellerId.trim();
    if (sellerId.isNotEmpty) sellers.add(sellerId);
  }
  return BuyerMarketplaceSnapshot(
    ownSociety: MarketplaceMetrics(
      activeSellerCount: sellers.length,
      availableListingCount: own.length,
    ),
    nearbyListings: nearby,
    neighbourhoodRadiusKm: homeDistanceCapKm(cityReach),
    neighbourHasListed: societyHasListedDish(
      listings,
      buyerSocietyId: buyerSocietyId,
    ),
  );
}
