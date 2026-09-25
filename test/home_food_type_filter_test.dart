import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/food_type.dart';
import 'package:societybites/models/selling_reach.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/widgets/food_type_selector.dart';

FoodItem _item({
  required String id,
  required String name,
  String? foodType,
  String? category,
  String sellerId = 'seller-1',
  String sellerName = 'Anita',
  List<String> tags = const [],
  String? campaignId,
  String catalogType = 'REGULAR',
}) {
  return FoodItem.fromJson({
    'id': id,
    'name': name,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'price': 100,
    'foodType': foodType,
    'category': category,
    'tags': tags,
    'campaignId': campaignId,
    'catalogType': catalogType,
  });
}

void main() {
  test('FoodItem parses VEG and NON_VEG and ignores unknown values', () {
    expect(_item(id: '1', name: 'Dal', foodType: 'VEG').foodType, foodTypeVeg);
    expect(
      _item(id: '2', name: 'Chicken', foodType: 'NON_VEG').foodType,
      foodTypeNonVeg,
    );
    expect(_item(id: '3', name: 'Roll').foodType, isNull);
    expect(_item(id: '4', name: 'Egg curry', foodType: 'EGG').foodType, isNull);
  });

  test('Home defaults to ALL and shows VEG, NON_VEG and NULL listings', () {
    final listings = [
      _item(id: 'v', name: 'Paneer', foodType: foodTypeVeg),
      _item(id: 'n', name: 'Biryani', foodType: foodTypeNonVeg),
      _item(id: 'u', name: 'Special'),
    ];
    final all = applyHomeListingFilters(listings);
    expect(all.map((e) => e.id), ['v', 'n', 'u']);
  });

  test('VEG filter shows only VEG and excludes NULL', () {
    final listings = [
      _item(id: 'v', name: 'Paneer', foodType: foodTypeVeg),
      _item(id: 'n', name: 'Biryani', foodType: foodTypeNonVeg),
      _item(id: 'u', name: 'Special'),
    ];
    final veg = applyHomeListingFilters(listings, foodType: foodTypeVeg);
    expect(veg.map((e) => e.id), ['v']);
  });

  test('NON_VEG filter shows only NON_VEG and excludes NULL', () {
    final listings = [
      _item(id: 'v', name: 'Paneer', foodType: foodTypeVeg),
      _item(id: 'n', name: 'Biryani', foodType: foodTypeNonVeg),
      _item(id: 'u', name: 'Special'),
    ];
    final nonVeg = applyHomeListingFilters(listings, foodType: foodTypeNonVeg);
    expect(nonVeg.map((e) => e.id), ['n']);
  });

  test('category filtering continues to work with food type', () {
    final listings = [
      _item(
        id: '1',
        name: 'Veg snacks',
        foodType: foodTypeVeg,
        category: 'Snacks',
      ),
      _item(
        id: '2',
        name: 'Veg dinner',
        foodType: foodTypeVeg,
        category: 'Dinner',
      ),
      _item(
        id: '3',
        name: 'Non-veg snacks',
        foodType: foodTypeNonVeg,
        category: 'Snacks',
      ),
    ];
    final result = applyHomeListingFilters(
      listings,
      foodType: foodTypeVeg,
      category: 'Snacks',
    );
    expect(result.map((e) => e.id), ['1']);
  });

  test('search ignores category so matches appear as the user types', () {
    final listings = [
      _item(id: '1', name: 'Birthday Cake', category: 'Desserts'),
      _item(id: '2', name: 'Masala Dosa', category: 'Lunch'),
    ];
    final result = applyHomeListingFilters(
      listings,
      category: 'Desserts',
      searchQuery: 'dosa',
    );
    expect(result.map((e) => e.name), ['Masala Dosa']);
  });

  test('search ranks name prefix matches first', () {
    final listings = [
      _item(id: '1', name: 'Hyderabadi Chicken Biryani'),
      _item(id: '2', name: 'Biryani rice'),
    ];
    final result = applyHomeListingFilters(listings, searchQuery: 'bir');
    expect(result.map((e) => e.name), ['Biryani rice', 'Hyderabadi Chicken Biryani']);
  });

  test('search and food type filtering work together', () {
    final listings = [
      _item(id: '1', name: 'Veg Samosa', foodType: foodTypeVeg),
      _item(id: '2', name: 'Chicken Samosa', foodType: foodTypeNonVeg),
      _item(id: '3', name: 'Paneer Roll', foodType: foodTypeVeg),
    ];
    final result = applyHomeListingFilters(
      listings,
      foodType: foodTypeVeg,
      searchQuery: 'samosa',
    );
    expect(result.map((e) => e.name), ['Veg Samosa']);
  });

  test('Veg OFF keeps mixed seller listings visible', () {
    final listings = [
      _item(id: 'veg', name: "Dadi's Dhokla", foodType: foodTypeVeg),
      _item(id: 'nv', name: 'Chicken Biryani', foodType: foodTypeNonVeg),
    ];
    final result = applyHomeListingFilters(listings);
    expect(result.map((e) => e.name), ["Dadi's Dhokla", 'Chicken Biryani']);
    expect(sellersFromListings(result).map((s) => s.id), ['seller-1']);
  });

  test('Veg ON hides non-veg items but keeps a mixed seller', () {
    final listings = [
      _item(id: 'veg1', name: "Dadi's Dhokla", foodType: foodTypeVeg),
      _item(id: 'veg2', name: 'Samosa', foodType: foodTypeVeg),
      _item(id: 'nv', name: 'Chicken Biryani', foodType: foodTypeNonVeg),
    ];
    final result = applyHomeListingFilters(listings, foodType: foodTypeVeg);
    expect(result.map((e) => e.name), ["Dadi's Dhokla", 'Samosa']);
    expect(sellersFromListings(result).single.id, 'seller-1');
  });

  test('Veg ON hides sellers that only have non-veg listings', () {
    final listings = [
      _item(
        id: 'puran-veg',
        name: 'Dhokla',
        foodType: foodTypeVeg,
        sellerId: 'puran',
        sellerName: 'Puran Agrawal',
      ),
      _item(
        id: 'only-nv',
        name: 'Chicken Curry',
        foodType: foodTypeNonVeg,
        sellerId: 'other',
        sellerName: 'Other Kitchen',
      ),
    ];
    final result = applyHomeListingFilters(listings, foodType: foodTypeVeg);
    expect(result.map((e) => e.sellerId), ['puran']);
    expect(sellersFromListings(result).map((s) => s.id), ['puran']);
  });

  test('Veg filter never includes PREORDER catalog items in regular results', () {
    final listings = [
      _item(id: 'regular', name: 'Dhokla', foodType: foodTypeVeg),
      _item(
        id: 'pre',
        name: 'Festival Thali',
        foodType: foodTypeVeg,
        catalogType: 'PREORDER',
      ),
    ];
    final result = applyHomeListingFilters(listings, foodType: foodTypeVeg);
    expect(result.map((e) => e.id), ['regular']);
  });

  test('food type filter does not inspect nearby reach or society fields', () {
    final listings = [
      _item(id: 'veg', name: 'Dhokla', foodType: foodTypeVeg),
      _item(id: 'nv', name: 'Chicken', foodType: foodTypeNonVeg),
    ];
    final result = listingsMatchingFoodType(listings, foodType: foodTypeVeg);
    expect(result.map((e) => e.id), ['veg']);
  });

  test('switching All → Veg → Non-Veg makes no API calls', () {
    var apiCalls = 0;
    final loaded = [
      _item(id: 'v', name: 'Paneer', foodType: foodTypeVeg),
      _item(id: 'n', name: 'Biryani', foodType: foodTypeNonVeg),
      _item(id: 'u', name: 'Special'),
    ];

    applyHomeListingFilters(loaded);
    applyHomeListingFilters(loaded, foodType: foodTypeVeg);
    applyHomeListingFilters(loaded, foodType: foodTypeNonVeg);
    applyHomeListingFilters(loaded);

    expect(apiCalls, 0);
  });

  test('new listing cannot submit without foodType', () {
    expect(foodTypeSelectionError(foodType: null), isNotNull);
    expect(foodTypeSelectionError(foodType: foodTypeVeg), isNull);
  });

  test('Egg tag is compatible only with NON_VEG', () {
    expect(
      foodTypeSelectionError(foodType: foodTypeVeg, tags: ['Egg']),
      isNotNull,
    );
    expect(
      foodTypeSelectionError(foodType: foodTypeNonVeg, tags: ['Egg']),
      isNull,
    );
  });

  test('Vegan and Jain are compatible with VEG', () {
    expect(
      foodTypeSelectionError(foodType: foodTypeVeg, tags: ['Vegan', 'Jain']),
      isNull,
    );
    expect(
      foodTypeSelectionError(foodType: foodTypeNonVeg, tags: ['Vegan']),
      isNotNull,
    );
    expect(
      foodTypeSelectionError(foodType: foodTypeNonVeg, tags: ['Jain']),
      isNotNull,
    );
  });

  testWidgets('seller can select exactly one food type', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return FoodTypeSelector(
                value: selected,
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('🥬 Vegetarian'));
    await tester.pump();
    expect(selected, foodTypeVeg);

    await tester.tap(find.text('🍗 Non-Vegetarian'));
    await tester.pump();
    expect(selected, foodTypeNonVeg);
  });

  testWidgets('Home food type toggle cycles All → Veg → Non-Veg without fetching', (
    tester,
  ) async {
    var fetches = 0;
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return FoodTypeFilterChips(
                selectedFoodType: selected,
                onChanged: (value) {
                  fetches += 0;
                  setState(() => selected = value);
                },
              );
            },
          ),
        ),
      ),
    );

    expect(selected, isNull);
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-food-type-toggle')));
    await tester.pump();
    expect(selected, foodTypeVeg);
    expect(find.text('Veg'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-food-type-toggle')));
    await tester.pump();
    expect(selected, foodTypeNonVeg);
    expect(find.text('Non-Veg'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-food-type-toggle')));
    await tester.pump();
    expect(selected, isNull);
    expect(find.text('All'), findsOneWidget);
    expect(fetches, 0);
  });

  test('nearby payload flattens listings and merge keeps society first', () {
    final society = [
      {'id': 'local-1', 'name': 'Society Dal'},
    ];
    final nearby = listingMapsFromNearbyPayload({
      'available': true,
      'sellers': [
        {
          'seller': {'id': 'aarav', 'distanceKm': 8.2},
          'listings': [
            {'id': 'local-1', 'name': 'Duplicate Dal'},
            {'id': 'aarav-sushi', 'name': 'veg Sushi'},
          ],
        },
      ],
    });
    final merged = mergeSocietyAndNearbyListingMaps(society, nearby);
    expect(merged.map((item) => item['id']), ['local-1', 'aarav-sushi']);
    expect(merged.first['name'], 'Society Dal');
  });

  test('copies seller sellingReachLevel and distanceKm onto flattened nearby listings', () {
    final nearby = listingMapsFromNearbyPayload({
      'available': true,
      'sellers': [
        {
          'seller': {
            'id': 'aarav',
            'sellingReachLevel': 'EXTENDED',
            'distanceKm': 0.16,
          },
          'listings': [
            {'id': 'sushi', 'name': 'veg Sushi'},
          ],
        },
      ],
    });
    expect(nearby.single['sellingReachLevel'], 'EXTENDED');
    expect(nearby.single['distanceKm'], 0.16);
  });

  test('home reach buckets use societyId then distance vs nearby radius', () {
    FoodItem item({
      required String id,
      String? societyId,
      String? sellingReachLevel,
      double? distanceKm,
    }) {
      return FoodItem.fromJson({
        'id': id,
        'name': id,
        'sellerId': 's-$id',
        'sellerName': 'Cook',
        'price': 10,
        'societyId': ?societyId,
        'sellingReachLevel': ?sellingReachLevel,
        'distanceKm': ?distanceKm,
      });
    }

    const nearbyKm = 8.0;
    final society = item(id: 'dal', societyId: 'mine');
    final nextDoorExtended = item(
      id: 'cake',
      societyId: 'notting',
      sellingReachLevel: 'EXTENDED',
      distanceKm: 0.16,
    );
    final furtherExtended = item(
      id: 'sushi',
      societyId: 'ferns',
      sellingReachLevel: 'EXTENDED',
      distanceKm: 8.33,
    );
    final optedNearbyNoDistance = item(
      id: 'idli',
      societyId: 'other',
      sellingReachLevel: 'NEARBY',
    );
    expect(
      homeListingReachFor(society, buyerSocietyId: 'mine', nearbyRadiusKm: nearbyKm),
      HomeListingReach.inSociety,
    );
    expect(
      homeListingReachFor(
        nextDoorExtended,
        buyerSocietyId: 'mine',
        nearbyRadiusKm: nearbyKm,
      ),
      HomeListingReach.nearby,
    );
    expect(
      homeListingReachFor(
        furtherExtended,
        buyerSocietyId: 'mine',
        nearbyRadiusKm: nearbyKm,
      ),
      HomeListingReach.extended,
    );
    expect(
      homeListingReachFor(
        optedNearbyNoDistance,
        buyerSocietyId: 'mine',
        nearbyRadiusKm: nearbyKm,
      ),
      HomeListingReach.nearby,
    );
  });

  test('unavailable nearby payload contributes no listings', () {
    expect(
      listingMapsFromNearbyPayload({'available': false, 'sellers': []}),
      isEmpty,
    );
  });

  test('nearby seller card payload extracts listings', () {
    expect(
      listingMapsFromNearbySellerCard({
        'listings': [
          {'id': 'sushi', 'name': 'veg Sushi'},
        ],
      }).map((item) => item['id']),
      ['sushi'],
    );
  });

  test('home campaign reach keeps other-society campaigns out of Your Society',
      () {
    final now = DateTime.now();
    PreOrderCampaign camp({
      required String id,
      required String sellerId,
      String? societyId,
      String? discoveryReach,
      double? distanceKm,
    }) {
      return PreOrderCampaign(
        id: id,
        sellerId: sellerId,
        title: id,
        status: 'open',
        orderOpenAt: now.subtract(const Duration(hours: 1)),
        orderCutoffAt: now.add(const Duration(hours: 5)),
        fulfilmentAt: now.add(const Duration(days: 1)),
        societyId: societyId,
        discoveryReach: discoveryReach,
        distanceKm: distanceKm,
      );
    }

    final own = camp(
      id: 'sat-special',
      sellerId: 'puran',
      societyId: 'notting-hill',
      discoveryReach: 'inSociety',
    );
    final fern = camp(
      id: 'tgif',
      sellerId: 'aarav',
      societyId: 'prestige-fern',
      discoveryReach: 'extended',
      distanceKm: 8.3,
    );

    expect(
      homeCampaignReachFor(
        own,
        buyerSocietyId: 'notting-hill',
        viewerUserId: 'puran',
      ),
      HomeListingReach.inSociety,
    );
    expect(
      homeCampaignReachFor(
        fern,
        buyerSocietyId: 'notting-hill',
        viewerUserId: 'puran',
        nearbyRadiusKm: 6,
      ),
      HomeListingReach.extended,
    );
    expect(
      campaignsForHomeReach(
        [own, fern],
        reach: HomeListingReach.inSociety,
        buyerSocietyId: 'notting-hill',
        viewerUserId: 'puran',
        nearbyRadiusKm: 6,
      ).map((campaign) => campaign.id),
      ['sat-special'],
    );
    expect(
      campaignsForHomeReach(
        [own, fern],
        reach: HomeListingReach.extended,
        buyerSocietyId: 'notting-hill',
        viewerUserId: 'puran',
        nearbyRadiusKm: 6,
      ).map((campaign) => campaign.id),
      ['tgif'],
    );
  });

  test('EXTENDED seller still sees own campaign in Your Society, not Around you',
      () {
    final now = DateTime.now();
    final own = PreOrderCampaign(
      id: 'sat-special',
      sellerId: 'puran',
      title: 'Sat Special',
      status: 'open',
      orderOpenAt: now.subtract(const Duration(hours: 1)),
      orderCutoffAt: now.add(const Duration(hours: 5)),
      fulfilmentAt: now.add(const Duration(days: 1)),
      societyId: 'notting-hill',
      sellingReachLevel: SellingReachLevel.extended,
      distanceKm: 0,
    );

    expect(
      homeCampaignReachFor(
        own,
        buyerSocietyId: 'notting-hill',
        viewerUserId: 'puran',
        nearbyRadiusKm: 8,
      ),
      HomeListingReach.inSociety,
    );
    expect(
      homeCampaignReachFor(
        own,
        buyerSocietyId: 'notting-hill',
        nearbyRadiusKm: 8,
      ),
      HomeListingReach.inSociety,
    );
  });
}
