import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/selling_reach.dart';
import 'package:societybites/models/food_type.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/widgets/listing_rating_mark.dart';

FoodItem _food(
  String name, {
  String status = 'active',
  int quantity = 4,
  String? societyId,
  double? distanceKm,
  double rating = 0,
  int reviewCount = 0,
  DateTime? createdAt,
  String? foodType = foodTypeVeg,
  String availabilityMode = listingAvailabilityReadyNow,
  bool recurringUnavailable = false,
  String? sellerId,
  String category = 'Snacks',
}) {
  return FoodItem.fromJson({
    'id': 'listing-$name',
    'name': name,
    'sellerId': sellerId ?? 'seller-$name',
    'sellerName': 'Anita',
    'price': 80,
    'status': status,
    'quantity': quantity,
    'foodType': foodType,
    'category': category,
    'catalogType': listingCatalogRegular,
    'availabilityMode': availabilityMode,
    'avgRating': rating,
    'reviewCount': reviewCount,
    if (societyId != null) 'societyId': societyId,
    if (distanceKm != null) 'distanceKm': distanceKm,
    if (createdAt != null) 'createdAt': createdAt.toIso8601String(),
    'recurringUnavailable': recurringUnavailable,
  });
}

void main() {
  final now = DateTime(2026, 10, 4, 18);

  test('New is the last 48 hours and rating is separate', () {
    final today = _food(
      'Today',
      createdAt: now.subtract(const Duration(hours: 5)),
    );
    final reviewed = _food(
      'Reviewed',
      createdAt: now.subtract(const Duration(hours: 20)),
      rating: 4.8,
      reviewCount: 5,
    );
    final quiet = _food(
      'Quiet',
      createdAt: now.subtract(const Duration(days: 3)),
    );
    final trusted = _food(
      'Trusted',
      createdAt: now.subtract(const Duration(days: 3)),
      rating: 4.7,
      reviewCount: 10,
    );
    final edge = _food(
      'Edge',
      createdAt: now.subtract(const Duration(hours: 48)),
    );
    final past = _food(
      'Past',
      createdAt: now.subtract(const Duration(hours: 48, seconds: 1)),
    );

    expect(today.isNewListing(now), isTrue);
    expect(today.reviewCount, 0);
    expect(reviewed.isNewListing(now), isTrue);
    expect(reviewed.reviewCount, 5);
    expect(quiet.isNewListing(now), isFalse);
    expect(trusted.isNewListing(now), isFalse);
    expect(edge.isNewListing(now), isTrue);
    expect(past.isNewListing(now), isFalse);
  });

  testWidgets('badge shows New with rating or no reviews', (tester) async {
    Future<void> pump(FoodItem food) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ListingRatingMark(food: food)),
        ),
      );
    }

    await pump(
      _food(
        'Fresh',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    );
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('0 review'), findsNothing);

    await pump(
      _food(
        'Rated',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        rating: 4.8,
        reviewCount: 5,
      ),
    );
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('0 review'), findsNothing);

    await pump(
      _food('Old', createdAt: DateTime.now().subtract(const Duration(days: 3))),
    );
    expect(find.text('NEW'), findsNothing);
    expect(find.text('0 review'), findsOneWidget);
  });

  test('paused, sold out, and expired leave the home feed', () {
    final names = applyHomeListingFilters([
      _food('Paused', status: 'paused'),
      _food('Gone', status: 'sold_out'),
      _food('Old', status: 'expired'),
      _food('Live'),
    ]).map((item) => item.name);
    expect(names, ['Live']);
  });

  test(
    'orderable, same society, then closer, then confident rating, then newer',
    () {
      final unavailable = _food(
        'Later',
        societyId: 'mine',
        distanceKm: 0,
        rating: 5,
        reviewCount: 20,
        recurringUnavailable: true,
      );
      final far = _food('Far', societyId: 'other', distanceKm: 8);
      final near = _food('Near', societyId: 'other', distanceKm: 1.2);
      final own = _food('Own', societyId: 'mine', distanceKm: 0);
      final oneReview = _food(
        'One',
        societyId: 'other',
        distanceKm: 4,
        rating: 5,
        reviewCount: 1,
      );
      final manyReviews = _food(
        'Many',
        societyId: 'other',
        distanceKm: 4,
        rating: 4.2,
        reviewCount: 12,
      );
      final newer = _food(
        'Newer',
        societyId: 'other',
        distanceKm: 4,
        createdAt: DateTime(2026, 10, 4),
      );
      final older = _food(
        'Older',
        societyId: 'other',
        distanceKm: 4,
        createdAt: DateTime(2026, 9, 1),
      );

      final ranked = applyHomeListingFilters(
        [far, oneReview, unavailable, older, near, manyReviews, newer, own],
        buyerSocietyId: 'mine',
        now: DateTime(2026, 12, 1),
      ).map((item) => item.name);

      expect(ranked, [
        'Own',
        'Near',
        'Many',
        'One',
        'Newer',
        'Older',
        'Far',
        'Later',
      ]);
    },
  );

  test('veg, made to order, and distance still filter before rank', () {
    final match = _food(
      'Cake',
      availabilityMode: listingAvailabilityMadeToOrder,
      distanceKm: 2,
      societyId: 'other',
    );
    final tooFar = _food(
      'Pie',
      availabilityMode: listingAvailabilityMadeToOrder,
      distanceKm: 6,
      societyId: 'other',
    );
    final ready = _food('Samosa', distanceKm: 1, societyId: 'other');
    final chicken = _food(
      'Chicken',
      foodType: foodTypeNonVeg,
      availabilityMode: listingAvailabilityMadeToOrder,
      distanceKm: 1,
      societyId: 'other',
    );

    final typed = applyHomeListingFilters(
      [ready, chicken, tooFar, match],
      foodType: foodTypeVeg,
      listingType: HomeListingType.madeToOrder,
    );
    final within = listingsMatchingBuyerDistance(
      typed,
      choice: const BuyerDistanceChoice.within(3),
      buyerSocietyId: 'mine',
    );
    expect(within.map((item) => item.name), ['Cake']);

    expect(
      applyHomeListingFilters([ready], listingType: HomeListingType.preOrder),
      isEmpty,
    );
  });

  test('distance menu uses the configured reach and keeps own society', () {
    final reach = SellingReach.fromJson({
      'nearbyRadiusKm': 5,
      'extendedRadiusKm': 14,
      'maxSellerRadiusKm': 10,
    });
    final choices = homeDistanceMenuChoices(reach);
    expect(homeDistanceMenuLabel(choices.first, reach), 'Up to 10 km');
    expect(choices.first.maxKm, 10);
    expect(
      choices.map((choice) => homeDistanceMenuLabel(choice, reach)).toList(),
      ['Up to 10 km', 'Up to 7 km', 'Up to 5 km', 'Up to 3 km', 'Up to 2 km', 'Up to 1 km'],
    );

    final fromNearbyPayload = SellingReach.fromAuthMe({
      'nearbyRadiusKm': 5,
      'extendedRadiusKm': 14,
      'appliedRadiusKm': 10,
    });
    expect(
      homeDistanceMenuLabel(
        homeDistanceMenuChoices(fromNearbyPayload).first,
        fromNearbyPayload,
      ),
      'Up to 10 km',
    );

    final wider = SellingReach.fromJson({
      'nearbyRadiusKm': 8,
      'extendedRadiusKm': 10,
    });
    expect(
      homeDistanceMenuChoices(
        wider,
      ).map((choice) => homeDistanceMenuLabel(choice, wider)),
      containsAll(['Up to 10 km', 'Up to 7 km']),
    );

    expect(
      foodMatchesBuyerDistance(
        _food('Own', societyId: 'mine'),
        choice: BuyerDistanceChoice.within(1),
        buyerSocietyId: 'mine',
      ),
      isTrue,
    );
  });

  test('just added is the last 48 hours, newest first', () {
    final now = DateTime(2026, 10, 5, 12);
    final hourAgo = _food(
      'Hour',
      createdAt: now.subtract(const Duration(hours: 1)),
      rating: 3.5,
      reviewCount: 2,
    );
    final twoHours = _food(
      'Two',
      createdAt: now.subtract(const Duration(hours: 2)),
      rating: 5,
      reviewCount: 30,
    );
    final fortySeven = _food(
      'Edge',
      createdAt: now.subtract(const Duration(hours: 47)),
    );
    final tooOld = _food(
      'Old',
      createdAt: now.subtract(const Duration(hours: 48, seconds: 1)),
      rating: 5,
      reviewCount: 40,
    );

    final names = applyHomeListingFilters(
      [tooOld, twoHours, fortySeven, hourAgo],
      justAdded: true,
      now: now,
    ).map((item) => item.name);

    expect(names, ['Hour', 'Two', 'Edge']);
  });

  test('default home keeps made to order beside ready-now dishes', () {
    final names = applyHomeListingFilters([
      _food('Samosa'),
      _food('Cake', availabilityMode: listingAvailabilityMadeToOrder),
    ], now: DateTime(2026, 12, 1)).map((item) => item.name);

    expect(names, containsAll(['Samosa', 'Cake']));
  });

  test('made to order and pre-order filters stay exclusive', () {
    final ready = _food('Samosa');
    final made = _food(
      'Cake',
      availabilityMode: listingAvailabilityMadeToOrder,
    );
    expect(
      applyHomeListingFilters([
        ready,
        made,
      ], listingType: HomeListingType.madeToOrder).map((item) => item.name),
      ['Cake'],
    );
    expect(
      applyHomeListingFilters([
        ready,
        made,
      ], listingType: HomeListingType.preOrder),
      isEmpty,
    );
  });

  test(
    'just added still honors veg, category, distance, and made to order',
    () {
      final now = DateTime(2026, 10, 5, 12);
      final match = _food(
        'Idli',
        category: 'Breakfast',
        availabilityMode: listingAvailabilityMadeToOrder,
        createdAt: now.subtract(const Duration(hours: 3)),
        distanceKm: 1,
        societyId: 'other',
      );
      final newerMatch = _food(
        'Dosa',
        category: 'Breakfast',
        availabilityMode: listingAvailabilityMadeToOrder,
        createdAt: now.subtract(const Duration(minutes: 10)),
        distanceKm: 2,
        societyId: 'other',
      );
      final chicken = _food(
        'Chicken',
        foodType: foodTypeNonVeg,
        category: 'Breakfast',
        availabilityMode: listingAvailabilityMadeToOrder,
        createdAt: now.subtract(const Duration(minutes: 1)),
        distanceKm: 1,
        societyId: 'other',
      );
      final lunch = _food(
        'Rice',
        category: 'Lunch',
        availabilityMode: listingAvailabilityMadeToOrder,
        createdAt: now.subtract(const Duration(minutes: 1)),
        distanceKm: 1,
        societyId: 'other',
      );
      final far = _food(
        'Far',
        category: 'Breakfast',
        availabilityMode: listingAvailabilityMadeToOrder,
        createdAt: now.subtract(const Duration(minutes: 1)),
        distanceKm: 9,
        societyId: 'other',
      );
      final old = _food(
        'Old',
        category: 'Breakfast',
        availabilityMode: listingAvailabilityMadeToOrder,
        createdAt: now.subtract(const Duration(days: 4)),
        distanceKm: 1,
        societyId: 'other',
      );

      final filtered = applyHomeListingFilters(
        [far, old, chicken, lunch, match, newerMatch],
        justAdded: true,
        now: now,
        foodType: foodTypeVeg,
        category: 'Breakfast',
        listingType: HomeListingType.madeToOrder,
      );
      final within = listingsMatchingBuyerDistance(
        filtered,
        choice: const BuyerDistanceChoice.within(3),
        buyerSocietyId: 'mine',
      );

      expect(within.map((item) => item.name), ['Dosa', 'Idli']);
    },
  );

  test('one five-star review does not outrank a well reviewed listing', () {
    final now = DateTime(2026, 12, 1);
    final thin = _food(
      'Thin',
      rating: 5,
      reviewCount: 1,
      societyId: 'mine',
      distanceKm: 0,
      createdAt: now.subtract(const Duration(days: 20)),
    );
    final trusted = _food(
      'Trusted',
      rating: 4.7,
      reviewCount: 25,
      societyId: 'mine',
      distanceKm: 0,
      createdAt: now.subtract(const Duration(days: 30)),
    );

    expect(homeConfidenceRating(thin), lessThan(homeConfidenceRating(trusted)));
    expect(
      applyHomeListingFilters(
        [thin, trusted],
        buyerSocietyId: 'mine',
        now: now,
      ).map((item) => item.name),
      ['Trusted', 'Thin'],
    );
  });

  test('a new listing outranks a one-review listing in the same place', () {
    final now = DateTime(2026, 10, 5, 12);
    final fresh = _food(
      'Fresh',
      societyId: 'mine',
      distanceKm: 0,
      createdAt: now.subtract(const Duration(hours: 1)),
    );
    final thin = _food(
      'Thin',
      rating: 5,
      reviewCount: 1,
      societyId: 'mine',
      distanceKm: 0,
      createdAt: now.subtract(const Duration(days: 10)),
    );
    final trusted = _food(
      'Trusted',
      rating: 4.7,
      reviewCount: 25,
      societyId: 'mine',
      distanceKm: 0,
      createdAt: now.subtract(const Duration(days: 40)),
    );

    expect(
      applyHomeListingFilters(
        [thin, trusted, fresh],
        buyerSocietyId: 'mine',
        now: now,
      ).map((item) => item.name),
      ['Trusted', 'Fresh', 'Thin'],
    );
  });

  test('one seller cannot fill Home with more than two dishes before others', () {
    final now = DateTime(2026, 10, 5, 12);
    final crowded = List.generate(
      4,
      (index) => _food(
        'A$index',
        sellerId: 'seller-a',
        societyId: 'mine',
        distanceKm: 0,
        createdAt: now.subtract(Duration(minutes: index)),
      ),
    );
    final other = _food(
      'Other',
      sellerId: 'seller-b',
      societyId: 'mine',
      distanceKm: 0,
      createdAt: now.subtract(const Duration(hours: 5)),
    );

    final names = applyHomeListingFilters(
      [...crowded, other],
      buyerSocietyId: 'mine',
      now: now,
    ).map((item) => item.name).toList();

    expect(names.take(3), ['A0', 'A1', 'Other']);
    expect(names, ['A0', 'A1', 'Other', 'A2', 'A3']);
    expect(homeMaxListingsPerSeller, 2);
    expect(homeAllItemsPreviewCount, 12);
  });

  test('per-seller cap also applies to older listings', () {
    final now = DateTime(2026, 12, 1);
    final crowded = List.generate(
      3,
      (index) => _food(
        'Old$index',
        sellerId: 'seller-a',
        societyId: 'mine',
        distanceKm: 0,
        rating: 5,
        reviewCount: 20 - index,
        createdAt: now.subtract(Duration(days: 10 + index)),
      ),
    );
    final other = _food(
      'Peer',
      sellerId: 'seller-b',
      societyId: 'mine',
      distanceKm: 0,
      rating: 4,
      reviewCount: 5,
      createdAt: now.subtract(const Duration(days: 12)),
    );

    final names = applyHomeListingFilters(
      [...crowded, other],
      buyerSocietyId: 'mine',
      now: now,
    ).map((item) => item.name).toList();

    expect(names.take(3), ['Old0', 'Old1', 'Peer']);
    // Sparse catalog (< 12) backfills the third dish after other sellers.
    expect(names, ['Old0', 'Old1', 'Peer', 'Old2']);
  });

  test('sparse catalog backfills more than two dishes from one seller', () {
    final now = DateTime(2026, 12, 1);
    final onlySeller = List.generate(
      5,
      (index) => _food(
        'Solo$index',
        sellerId: 'seller-solo',
        societyId: 'mine',
        distanceKm: 0,
        rating: 5,
        reviewCount: 10,
        createdAt: now.subtract(Duration(days: index + 1)),
      ),
    );

    final names = applyHomeListingFilters(
      onlySeller,
      buyerSocietyId: 'mine',
      now: now,
    ).map((item) => item.name).toList();

    expect(names.length, 5);
    expect(names, ['Solo0', 'Solo1', 'Solo2', 'Solo3', 'Solo4']);
  });

  test('per-seller cap after reach filter does not revive deferred dishes', () {
    final now = DateTime(2026, 12, 1);
    final sirisha = List.generate(
      4,
      (index) => _food(
        'S$index',
        sellerId: 'sirisha',
        societyId: 'mine',
        distanceKm: 0,
        rating: 5,
        reviewCount: 20,
        createdAt: now.subtract(Duration(days: index + 1)),
      ),
    );
    final beyond = List.generate(
      6,
      (index) => _food(
        'B$index',
        sellerId: 'beyond-$index',
        societyId: 'other',
        distanceKm: 2,
        rating: 4,
        reviewCount: 8,
        createdAt: now.subtract(Duration(days: index + 1)),
      ),
    );
    final ranked = applyHomeListingFilters(
      [...sirisha, ...beyond],
      buyerSocietyId: 'mine',
      now: now,
    );
    final inSociety = limitListingsPerSeller(
      ranked.where((food) => food.societyId == 'mine').toList(),
      fillTarget: 0,
    );
    expect(
      inSociety.take(2).where((food) => food.sellerId == 'sirisha').length,
      2,
    );
    expect(
      inSociety.where((food) => food.sellerId == 'sirisha').length,
      4,
    );
  });

  test('crowded feed keeps two-per-seller in the first preview slots', () {
    final now = DateTime(2026, 12, 1);
    final sellers = <FoodItem>[];
    for (var s = 0; s < 8; s++) {
      for (var i = 0; i < 3; i++) {
        sellers.add(
          _food(
            'S${s}L$i',
            sellerId: 'seller-$s',
            societyId: 'mine',
            distanceKm: 0,
            rating: 5,
            reviewCount: 20 - s,
            createdAt: now.subtract(Duration(days: s * 3 + i + 1)),
          ),
        );
      }
    }

    final names = applyHomeListingFilters(
      sellers,
      buyerSocietyId: 'mine',
      now: now,
    ).map((item) => item.name).toList();

    final preview = names.take(homeAllItemsPreviewCount).toList();
    final perSeller = <String, int>{};
    for (final name in preview) {
      final seller = name.substring(0, name.indexOf('L'));
      perSeller[seller] = (perSeller[seller] ?? 0) + 1;
    }
    expect(perSeller.values.every((count) => count <= 2), isTrue);
    expect(perSeller.length, greaterThanOrEqualTo(6));
  });
}
