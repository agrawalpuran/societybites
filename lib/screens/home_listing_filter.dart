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
  HomeListingType listingType = HomeListingType.all,
  String? buyerSocietyId,
  bool includeNotSelling = false,
  bool excludeFssaiBlockedFromBuyerFeed = false,
  bool justAdded = false,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  var results = listings
      .where(
        (food) =>
            (food.isEligibleForHomeFeed ||
                (includeNotSelling && (food.isExpired || food.isSoldOut))) &&
            !food.isPreOrder &&
            !food.isPreOrderCatalog,
      )
      .toList();
  results = listingsMatchingFoodType(results, foodType: foodType);
  results = listingsMatchingHomeType(results, listingType);
  if (justAdded) {
    results = results.where((food) => food.isNewListing(clock)).toList();
  }

  if (category != null && category != 'All' && searchQuery.trim().isEmpty) {
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

  final indexed = results.asMap().entries.toList();
  indexed.sort((a, b) {
    if (justAdded) {
      final byCreated = _homeCreatedAt(
        b.value,
      ).compareTo(_homeCreatedAt(a.value));
      if (byCreated != 0) return byCreated;
      return a.key.compareTo(b.key);
    }
    final rank = compareHomeFeedListings(
      a.value,
      b.value,
      buyerSocietyId: buyerSocietyId,
      now: clock,
    );
    if (rank != 0) return rank;
    if (searchQuery.isNotEmpty) {
      final search = homeSearchMatchScore(
        a.value,
        searchQuery,
      ).compareTo(homeSearchMatchScore(b.value, searchQuery));
      if (search != 0) return search;
    }
    return a.key.compareTo(b.key);
  });
  results = indexed.map((entry) => entry.value).toList();
  if (!justAdded) {
    results = _limitNewListingsPerSeller(results, now: clock);
  }

  if (excludeFssaiBlockedFromBuyerFeed) {
    results = results.where((food) => !food.blockedBySellerFssai).toList();
  }

  return results;
}

/// Buyer Home type filter. All keeps today's feed.
enum HomeListingType { all, regular, madeToOrder, preOrder }

/// Regular is a ready-now listing: not made to order, and not a pre-order
/// catalog item. [applyHomeListingFilters] already drops pre-order catalog
/// items before this runs.
List<FoodItem> listingsMatchingHomeType(
  Iterable<FoodItem> listings,
  HomeListingType type,
) {
  switch (type) {
    case HomeListingType.all:
      return List<FoodItem>.from(listings);
    case HomeListingType.regular:
      return listings.where((food) => !food.isMadeToOrder).toList();
    case HomeListingType.madeToOrder:
      return listings.where((food) => food.isMadeToOrder).toList();
    case HomeListingType.preOrder:
      return <FoodItem>[];
  }
}

/// Pre-order campaigns already loaded for Home. Category is not stored on
/// a campaign, so a category selection matches none of them.
List<PreOrderCampaign> campaignsMatchingHomeTypeFilters(
  Iterable<PreOrderCampaign> campaigns, {
  String? foodType,
  String searchQuery = '',
  String? category,
}) {
  if (category != null && category != 'All') return const [];
  final selectedType = parseFoodType(foodType);
  var results = campaigns.toList();
  if (selectedType != null) {
    results = results
        .where(
          (campaign) => campaign.products.any(
            (product) => product.foodType == selectedType,
          ),
        )
        .toList();
  }
  final query = searchQuery.trim().toLowerCase();
  if (query.isEmpty) return results;
  return results.where((campaign) {
    if (campaign.title.toLowerCase().contains(query)) return true;
    if ((campaign.description ?? '').toLowerCase().contains(query)) {
      return true;
    }
    if (campaign.sellerName.toLowerCase().contains(query)) return true;
    return campaign.products.any(
      (product) =>
          product.name.toLowerCase().contains(query) ||
          product.sellerName.toLowerCase().contains(query),
    );
  }).toList();
}

/// Orderable now, then own society, then closer, then discovery score,
/// then newer. Search relevance only breaks remaining ties.
int compareHomeFeedListings(
  FoodItem a,
  FoodItem b, {
  String? buyerSocietyId,
  DateTime? now,
}) {
  final orderable = (b.canAddToCart ? 1 : 0).compareTo(a.canAddToCart ? 1 : 0);
  if (orderable != 0) return orderable;

  final society = (_homeSameSociety(b, buyerSocietyId) ? 1 : 0).compareTo(
    _homeSameSociety(a, buyerSocietyId) ? 1 : 0,
  );
  if (society != 0) return society;

  final distance = _homeDistanceRank(
    a,
    buyerSocietyId,
  ).compareTo(_homeDistanceRank(b, buyerSocietyId));
  if (distance != 0) return distance;

  final clock = now ?? DateTime.now();
  final discovery = homeDiscoveryScore(
    b,
    clock,
  ).compareTo(homeDiscoveryScore(a, clock));
  if (discovery != 0) return discovery;

  return _homeCreatedAt(b).compareTo(_homeCreatedAt(a));
}

DateTime _homeCreatedAt(FoodItem food) {
  return food.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// Home chip for listings created within [FoodItem.newListingWindow].
const homeJustAddedFilter = 'Just Added';

/// Added to a new listing's discovery score. Large enough to pass a
/// one-review 5-star score, and smaller than a full rating from 10+ reviews.
const homeFreshnessBoost = 2.0;

/// At most this many new listings from one seller in the first Home preview.
const homeMaxNewListingsPerSeller = 2;

/// Review-confidence score plus a temporary boost for listings under 48 hours.
double homeDiscoveryScore(FoodItem food, DateTime now) {
  final fresh = food.isNewListing(now) ? homeFreshnessBoost : 0.0;
  return homeConfidenceRating(food) + fresh;
}

/// Full rating once a listing has 10 reviews. Fewer reviews count less,
/// so one 5-star review stays weak evidence.
double homeConfidenceRating(FoodItem food) {
  if (food.reviewCount <= 0 || food.rating <= 0) return 0;
  final trust = food.reviewCount >= 10 ? 1.0 : food.reviewCount / 10;
  return food.rating * trust;
}

bool _homeSameSociety(FoodItem food, String? buyerSocietyId) {
  final buyer = buyerSocietyId?.trim();
  final seller = food.societyId?.trim();
  if (buyer == null || buyer.isEmpty || seller == null || seller.isEmpty) {
    return false;
  }
  return buyer == seller;
}

double _homeDistanceRank(FoodItem food, String? buyerSocietyId) {
  if (_homeSameSociety(food, buyerSocietyId)) return 0;
  final km = food.distanceKm;
  if (km == null) return double.infinity;
  return km;
}

/// Keeps one seller's brand-new dishes from filling the whole preview when
/// another listing can take that slot. Does nothing when no alternative exists.
List<FoodItem> _limitNewListingsPerSeller(
  List<FoodItem> ranked, {
  required DateTime now,
}) {
  if (ranked.length <= 1) return ranked;
  final head = <FoodItem>[];
  final deferred = <FoodItem>[];
  final newCounts = <String, int>{};
  for (var i = 0; i < ranked.length; i++) {
    final food = ranked[i];
    if (head.length >= homeAllItemsPreviewCount) {
      deferred.add(food);
      continue;
    }
    final isNew = food.isNewListing(now);
    final used = newCounts[food.sellerId] ?? 0;
    if (isNew &&
        used >= homeMaxNewListingsPerSeller &&
        _laterListingCanFillPreview(ranked, i, food.sellerId, now)) {
      deferred.add(food);
      continue;
    }
    head.add(food);
    if (isNew) newCounts[food.sellerId] = used + 1;
  }
  return [...head, ...deferred];
}

bool _laterListingCanFillPreview(
  List<FoodItem> ranked,
  int index,
  String sellerId,
  DateTime now,
) {
  for (var j = index + 1; j < ranked.length; j++) {
    final other = ranked[j];
    if (!other.isNewListing(now) || other.sellerId != sellerId) return true;
  }
  return false;
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

/// Compact Home distance menu. The widest step is the city's configured reach.
const homeDistanceMenuStepsKm = <double>[1, 2, 3, 5, 7];

double? homeDistanceCapKm(SellingReach reach) =>
    reach.extendedRadiusKm ?? reach.nearbyRadiusKm;

List<BuyerDistanceChoice> homeDistanceMenuChoices(SellingReach reach) {
  final cap = homeDistanceCapKm(reach);
  if (cap == null || cap <= 0) {
    return const [BuyerDistanceChoice.extended()];
  }
  final narrower = <double>[
    for (final km in homeDistanceMenuStepsKm)
      if (km < cap - 0.001) km,
  ]..sort((a, b) => b.compareTo(a));
  final widest = reach.extendedAvailable
      ? const BuyerDistanceChoice.extended()
      : BuyerDistanceChoice.within(cap);
  return [widest, for (final km in narrower) BuyerDistanceChoice.within(km)];
}

String homeDistanceMenuLabel(BuyerDistanceChoice choice, SellingReach reach) {
  if (choice.societyOnly) return 'My Society';
  final km = choice.isExtended ? homeDistanceCapKm(reach) : choice.maxKm;
  if (km == null) return 'Nearby';
  return 'Up to ${formatBuyerDistanceKm(km)}';
}

String homeDishCountLabel(
  int count,
  BuyerDistanceChoice choice,
  SellingReach reach,
) {
  final noun = count == 1 ? 'dish' : 'dishes';
  if (choice.societyOnly) return '$count $noun in your society';
  final km = choice.isExtended ? homeDistanceCapKm(reach) : choice.maxKm;
  if (km == null) return '$count $noun nearby';
  return '$count $noun within ${formatBuyerDistanceKm(km)}';
}

String homeListingTypeLabel(HomeListingType type) {
  switch (type) {
    case HomeListingType.all:
      return 'All';
    case HomeListingType.regular:
      return 'Regular';
    case HomeListingType.madeToOrder:
      return 'Made to Order';
    case HomeListingType.preOrder:
      return 'Pre-order';
  }
}

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
    final societyName = (sellerInfo['societyName'] ?? seller['societyName'])
        ?.toString();
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
