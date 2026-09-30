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

/// Buyer-side Home distance. A null selection means the widest option,
/// which is today's full feed.
class BuyerDistanceChoice {
  const BuyerDistanceChoice.mySociety() : maxKm = null, societyOnly = true;

  const BuyerDistanceChoice.within(this.maxKm) : societyOnly = false;

  const BuyerDistanceChoice.extended() : maxKm = null, societyOnly = false;

  final double? maxKm;
  final bool societyOnly;

  bool get isExtended => !societyOnly && maxKm == null;

  String get optionKey {
    if (societyOnly) return 'mySociety';
    if (maxKm == null) return 'extended';
    return maxKm.toString();
  }

  @override
  bool operator ==(Object other) {
    return other is BuyerDistanceChoice &&
        other.societyOnly == societyOnly &&
        other.maxKm == maxKm;
  }

  @override
  int get hashCode => Object.hash(societyOnly, maxKm);
}

const _buyerDistanceStepsKm = <double>[0.5, 1, 2, 3, 5, 7, 10];

BuyerDistanceChoice effectiveBuyerDistance(
  BuyerDistanceChoice? selected,
  SellingReach reach,
) {
  final choices = buyerDistanceChoices(reach);
  if (selected != null && choices.contains(selected)) return selected;
  return choices.last;
}

List<BuyerDistanceChoice> buyerDistanceChoices(SellingReach reach) {
  final cap = reach.extendedRadiusKm ?? reach.nearbyRadiusKm;
  final steps = <double>{};
  if (cap != null && cap > 0) {
    for (final km in _buyerDistanceStepsKm) {
      if (km < cap) steps.add(km);
    }
    final nearby = reach.nearbyRadiusKm;
    if (nearby != null && nearby > 0 && nearby < cap) steps.add(nearby);
  }
  final sorted = steps.toList()..sort();
  return [
    const BuyerDistanceChoice.mySociety(),
    for (final km in sorted) BuyerDistanceChoice.within(km),
    if (cap != null && reach.extendedAvailable)
      const BuyerDistanceChoice.extended()
    else if (cap != null)
      BuyerDistanceChoice.within(cap),
  ];
}

String formatBuyerDistanceKm(double km) {
  if (km > 0 && km < 1) {
    return '${(km * 1000).round()} m';
  }
  final text = km == km.roundToDouble()
      ? km.toInt().toString()
      : km.toStringAsFixed(1);
  return '$text km';
}

String buyerDistanceLabel(BuyerDistanceChoice choice, SellingReach _) {
  if (choice.societyOnly) return 'My Society';
  if (choice.isExtended) return 'Extended';
  return 'Within ${formatBuyerDistanceKm(choice.maxKm!)}';
}

String buyerDistanceSubtitle(BuyerDistanceChoice choice, SellingReach reach) {
  if (choice.societyOnly) return 'Listings from your own society';
  if (choice.isExtended) {
    final km = reach.extendedRadiusKm;
    if (km == null) return 'The widest range available';
    return 'Up to ${formatBuyerDistanceKm(km)}';
  }
  return 'Up to ${formatBuyerDistanceKm(choice.maxKm!)}';
}

/// Hides dishes already outside the chosen radius. Extended keeps the feed
/// the server already returned, including dishes with no distance.
bool foodMatchesBuyerDistance(
  FoodItem food, {
  required BuyerDistanceChoice choice,
  required String? buyerSocietyId,
  double? nearbyRadiusKm,
}) {
  if (choice.isExtended) return true;
  final band = homeListingReachFor(
    food,
    buyerSocietyId: buyerSocietyId,
    nearbyRadiusKm: nearbyRadiusKm,
  );
  if (band == HomeListingReach.inSociety) return true;
  final km = food.distanceKm;
  if (choice.societyOnly) {
    return band == null && (km == null || km <= 0);
  }
  if (km == null) return band != HomeListingReach.extended;
  return km <= choice.maxKm!;
}

bool campaignMatchesBuyerDistance(
  PreOrderCampaign campaign, {
  required BuyerDistanceChoice choice,
  required String? buyerSocietyId,
  String? viewerUserId,
  double? nearbyRadiusKm,
}) {
  if (choice.isExtended) return true;
  final band = homeCampaignReachFor(
    campaign,
    buyerSocietyId: buyerSocietyId,
    viewerUserId: viewerUserId,
    nearbyRadiusKm: nearbyRadiusKm,
  );
  if (band == HomeListingReach.inSociety) return true;
  final km = campaign.distanceKm;
  if (choice.societyOnly) {
    return band == null && (km == null || km <= 0);
  }
  if (km == null) return band != HomeListingReach.extended;
  return km <= choice.maxKm!;
}

List<FoodItem> listingsMatchingBuyerDistance(
  Iterable<FoodItem> listings, {
  required BuyerDistanceChoice choice,
  required String? buyerSocietyId,
  double? nearbyRadiusKm,
}) {
  return listings
      .where(
        (food) => foodMatchesBuyerDistance(
          food,
          choice: choice,
          buyerSocietyId: buyerSocietyId,
          nearbyRadiusKm: nearbyRadiusKm,
        ),
      )
      .toList();
}

List<PreOrderCampaign> campaignsMatchingBuyerDistance(
  Iterable<PreOrderCampaign> campaigns, {
  required BuyerDistanceChoice choice,
  required String? buyerSocietyId,
  String? viewerUserId,
  double? nearbyRadiusKm,
}) {
  return campaigns
      .where(
        (campaign) => campaignMatchesBuyerDistance(
          campaign,
          choice: choice,
          buyerSocietyId: buyerSocietyId,
          viewerUserId: viewerUserId,
          nearbyRadiusKm: nearbyRadiusKm,
        ),
      )
      .toList();
}

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
    final societyName =
        (sellerInfo['societyName'] ?? seller['societyName'])?.toString();
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
      final society = societyName?.trim();
      if (society != null &&
          society.isNotEmpty &&
          (map['sellerSocietyName'] == null ||
              map['sellerSocietyName'].toString().trim().isEmpty)) {
        map['sellerSocietyName'] = society;
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
  final seller = payload['seller'] is Map
      ? Map<String, dynamic>.from(payload['seller'] as Map)
      : const <String, dynamic>{};
  final distanceKm = seller['distanceKm'] ?? payload['distanceKm'];
  final societyName = seller['societyName']?.toString().trim();
  return listings.whereType<Map>().map((item) {
    final map = Map<String, dynamic>.from(item);
    if (distanceKm != null && map['distanceKm'] == null) {
      map['distanceKm'] = distanceKm;
    }
    if (societyName != null &&
        societyName.isNotEmpty &&
        (map['sellerSocietyName'] == null ||
            map['sellerSocietyName'].toString().trim().isEmpty)) {
      map['sellerSocietyName'] = societyName;
    }
    return map;
  }).toList();
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
