import '../models/data.dart';
import '../models/food_type.dart';
import '../models/listing_categories.dart';
import '../models/selling_reach.dart';

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

  if (category != null &&
      category != 'All' &&
      searchQuery.trim().isEmpty) {
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
    if (aRank != bRank) return aRank.compareTo(bRank);
    if (searchQuery.isEmpty) return 0;
    return homeSearchMatchScore(a, searchQuery).compareTo(
      homeSearchMatchScore(b, searchQuery),
    );
  });

  return results;
}

int homeSearchMatchScore(FoodItem food, String searchQuery) {
  final q = searchQuery.trim().toLowerCase();
  if (q.isEmpty) return 0;
  final name = food.name.toLowerCase();
  final seller = food.sellerName.toLowerCase();
  if (name.startsWith(q)) return 0;
  if (name.split(RegExp(r'\s+')).any((word) => word.startsWith(q))) return 1;
  if (name.contains(q)) return 2;
  if (seller.startsWith(q)) return 3;
  return 4;
}

/// Home "All Items" first-screen cap. Remaining listings open via See all.
const homeAllItemsPreviewCount = 12;

/// Horizontal reach-section preview on Home.
const homeReachPreviewCount = 6;

enum HomeListingReach { inSociety, nearby, extended }

/// Own society first. Cross-society Home groups by distance vs the city
/// nearby radius (already returned on nearby-sellers), not by the seller's
/// opted-in level. Opted-in level only decides who is eligible to appear.
HomeListingReach? homeListingReachFor(
  FoodItem food, {
  required String? buyerSocietyId,
  double? nearbyRadiusKm,
}) {
  final listingSociety = food.societyId?.trim();
  final buyer = buyerSocietyId?.trim();
  if (buyer != null &&
      buyer.isNotEmpty &&
      listingSociety != null &&
      listingSociety.isNotEmpty &&
      listingSociety == buyer) {
    return HomeListingReach.inSociety;
  }
  final distance = food.distanceKm;
  final nearbyKm = nearbyRadiusKm;
  if (distance != null && nearbyKm != null) {
    if (distance <= nearbyKm) return HomeListingReach.nearby;
    return HomeListingReach.extended;
  }
  switch (food.sellerSellingReachLevel) {
    case SellingReachLevel.nearby:
      return HomeListingReach.nearby;
    case SellingReachLevel.extended:
      return HomeListingReach.extended;
    case SellingReachLevel.mySociety:
    case null:
      return null;
  }
}

List<FoodItem> listingsForHomeReach(
  Iterable<FoodItem> listings, {
  required HomeListingReach reach,
  required String? buyerSocietyId,
  double? nearbyRadiusKm,
}) {
  return listings
      .where(
        (food) =>
            homeListingReachFor(
              food,
              buyerSocietyId: buyerSocietyId,
              nearbyRadiusKm: nearbyRadiusKm,
            ) ==
            reach,
      )
      .toList();
}

HomeListingReach? homeCampaignReachFor(
  PreOrderCampaign campaign, {
  required String? buyerSocietyId,
  String? viewerUserId,
  double? nearbyRadiusKm,
}) {
  if (viewerUserId != null &&
      viewerUserId.isNotEmpty &&
      campaign.sellerId == viewerUserId) {
    return HomeListingReach.inSociety;
  }
  switch (campaign.discoveryReach) {
    case 'inSociety':
      return HomeListingReach.inSociety;
    case 'nearby':
      return HomeListingReach.nearby;
    case 'extended':
      return HomeListingReach.extended;
  }
  final campaignSociety = campaign.societyId?.trim();
  final buyer = buyerSocietyId?.trim();
  if (buyer != null &&
      buyer.isNotEmpty &&
      campaignSociety != null &&
      campaignSociety.isNotEmpty &&
      campaignSociety == buyer) {
    return HomeListingReach.inSociety;
  }
  final distance = campaign.distanceKm;
  if (distance != null && distance <= 0) {
    return HomeListingReach.inSociety;
  }
  final nearbyKm = nearbyRadiusKm;
  if (distance != null && nearbyKm != null) {
    if (distance <= nearbyKm) return HomeListingReach.nearby;
    return HomeListingReach.extended;
  }
  return null;
}

List<PreOrderCampaign> campaignsForHomeReach(
  Iterable<PreOrderCampaign> campaigns, {
  required HomeListingReach reach,
  required String? buyerSocietyId,
  String? viewerUserId,
  double? nearbyRadiusKm,
}) {
  return campaigns
      .where(
        (campaign) =>
            homeCampaignReachFor(
              campaign,
              buyerSocietyId: buyerSocietyId,
              viewerUserId: viewerUserId,
              nearbyRadiusKm: nearbyRadiusKm,
            ) ==
            reach,
      )
      .toList();
}

/// Flatten Explore Nearby seller cards into listing maps for the Home feed.
List<Map<String, dynamic>> listingMapsFromNearbyPayload(
  Map<String, dynamic> payload,
) {
  if (payload['available'] == false) return const [];
  final sellers = payload['sellers'];
  if (sellers is! List) return const [];
  final listings = <Map<String, dynamic>>[];
  for (final seller in sellers) {
    if (seller is! Map) continue;
    final sellerInfo = seller['seller'] is Map
        ? Map<String, dynamic>.from(seller['seller'] as Map)
        : const <String, dynamic>{};
    final reach = sellerInfo['sellingReachLevel'];
    final distanceKm = sellerInfo['distanceKm'] ?? seller['distanceKm'];
    final items = seller['listings'];
    if (items is! List) continue;
    for (final item in items) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      if (reach != null && map['sellingReachLevel'] == null) {
        map['sellingReachLevel'] = reach;
      }
      if (distanceKm != null && map['distanceKm'] == null) {
        map['distanceKm'] = distanceKm;
      }
      listings.add(map);
    }
  }
  return listings;
}

/// Listing maps from GET /listings/nearby-sellers/:sellerId.
List<Map<String, dynamic>> listingMapsFromNearbySellerCard(
  Map<String, dynamic> payload,
) {
  final listings = payload['listings'];
  if (listings is! List) return const [];
  return listings
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

/// Society listings first; nearby listings fill in without duplicating ids.
List<Map<String, dynamic>> mergeSocietyAndNearbyListingMaps(
  List<Map<String, dynamic>> societyListings,
  List<Map<String, dynamic>> nearbyListings,
) {
  final seen = <String>{};
  final merged = <Map<String, dynamic>>[];
  for (final item in [...societyListings, ...nearbyListings]) {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || !seen.add(id)) continue;
    merged.add(item);
  }
  return merged;
}
