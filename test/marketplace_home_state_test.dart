import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/home/adaptive_home.dart';
import 'package:societybites/home/chef_hunt_card.dart';
import 'package:societybites/home/discovery_home.dart';
import 'package:societybites/home/marketplace_home_state.dart';
import 'package:societybites/home/marketplace_metrics.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/selling_reach.dart';
import 'package:societybites/screens/home_screen.dart';
import 'package:societybites/services/session_service.dart';

MarketplaceMetrics _metrics(int sellers, int listings) {
  return MarketplaceMetrics(
    activeSellerCount: sellers,
    availableListingCount: listings,
  );
}

FoodItem _food(
  String id,
  String sellerId, {
  String status = 'active',
  String catalogType = 'REGULAR',
  bool fssaiBlocked = false,
  String societyId = 'society-1',
  double? distanceKm,
}) {
  return FoodItem.fromJson({
    'id': id,
    'name': id,
    'sellerId': sellerId,
    'sellerName': sellerId,
    'price': 80,
    'status': status,
    'quantity': 4,
    'catalogType': catalogType,
    'availabilityMode': 'READY_NOW',
    'foodType': 'VEG',
    'category': 'Snacks',
    'societyId': societyId,
    'distanceKm': ?distanceKm,
    if (distanceKm != null) 'sellingReachLevel': 'BEYOND_SOCIETY',
    if (fssaiBlocked) 'sellerAcceptingOrders': false,
    if (fssaiBlocked) 'sellerOrderBlockReason': 'FSSAI approval pending',
  });
}

void main() {
  test('zero listings is Discovery even when a seller count is present', () {
    expect(
      resolveMarketplaceState(_metrics(0, 0)),
      MarketplaceHomeState.discovery,
    );
    expect(
      resolveMarketplaceState(_metrics(6, 0)),
      MarketplaceHomeState.discovery,
    );
  });

  test('Growing covers every case below both Active thresholds', () {
    final cases = <(int, int)>[
      (0, 5),
      (1, 1),
      (2, 10),
      (4, 19),
      (5, 19),
      (4, 20),
    ];
    for (final row in cases) {
      expect(
        resolveMarketplaceState(_metrics(row.$1, row.$2)),
        MarketplaceHomeState.growing,
        reason: 'sellers ${row.$1}, listings ${row.$2}',
      );
    }
  });

  test('Active requires both thresholds', () {
    expect(
      resolveMarketplaceState(_metrics(5, 20)),
      MarketplaceHomeState.active,
    );
    expect(
      resolveMarketplaceState(_metrics(10, 100)),
      MarketplaceHomeState.active,
    );
    expect(
      resolveMarketplaceState(_metrics(5, 19)),
      isNot(MarketplaceHomeState.active),
    );
    expect(
      resolveMarketplaceState(_metrics(4, 20)),
      isNot(MarketplaceHomeState.active),
    );
  });

  test('changing either count can change the state', () {
    expect(
      resolveMarketplaceState(_metrics(5, 19)),
      MarketplaceHomeState.growing,
    );
    expect(
      resolveMarketplaceState(_metrics(5, 20)),
      MarketplaceHomeState.active,
    );
    expect(
      resolveMarketplaceState(_metrics(4, 20)),
      MarketplaceHomeState.growing,
    );
    expect(
      resolveMarketplaceState(_metrics(5, 0)),
      MarketplaceHomeState.discovery,
    );
  });

  test('own-society metrics ignore nearby, expired, and blocked dishes', () {
    final listings = [
      _food('a', 'seller-1'),
      _food('b', 'seller-1'),
      _food('near', 'seller-9', societyId: 'society-2', distanceKm: 4),
      _food('c', 'seller-2', status: 'expired'),
      _food('d', 'seller-3', status: 'paused'),
      _food('e', 'seller-4', catalogType: 'PREORDER'),
      _food('f', 'seller-5', fssaiBlocked: true),
    ];
    final snapshot = buyerMarketplaceSnapshot(
      listings,
      buyerSocietyId: 'society-1',
      cityReach: const SellingReach(extendedRadiusKm: 10, nearbyRadiusKm: 5),
    );
    expect(snapshot.ownSociety.availableListingCount, 2);
    expect(snapshot.ownSociety.activeSellerCount, 1);
    expect(snapshot.nearbyListings.map((food) => food.id), ['near']);
    expect(snapshot.neighbourhoodRadiusKm, 10);
  });

  testWidgets('an empty loaded feed selects the Discovery placeholder', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Homemade Food is Coming to Your Society'), findsOneWidget);
    expect(
      find.text(
        'No home kitchens are selling in your society or neighbourhood yet.',
      ),
      findsOneWidget,
    );
    expect(
      discoveryEmptyKitchenLine(10),
      'No home kitchens are selling in your society or within ~10 km yet.',
    );
    expect(find.text('What neighbours love to cook'), findsOneWidget);
    expect(find.text('Why Cook on SocietyEats?'), findsOneWidget);
    expect(find.text('RESIDENT CHEF PROGRAM'), findsNothing);
    expect(find.text('Ordering today from nearby societies'), findsNothing);
    expect(find.text('Invite neighbours'), findsNothing);
    expect(find.text('Search dishes or kitchens'), findsNothing);
    expect(find.text('No sellers available in your society yet'), findsNothing);
    expect(find.text('Invite via WhatsApp'), findsNothing);
  });

  testWidgets('a seller with a product does not see the cook invite', (tester) async {
    addTearDown(SessionService.clear);
    SharedPreferences.setMockInitialValues({
      'society_id': 'society-1',
      'user_role': 'seller',
      'auth_token': 'test-token',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
          onStartSelling: () {},
          readProfile: () async => {'id': 'seller-1', 'role': 'seller'},
          readOwnListings: () async => const [
            {'id': 'listing-1'},
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Homemade Food is Coming to Your Society'), findsOneWidget);
    expect(find.text('Why Cook on SocietyEats?'), findsNothing);
    expect(find.text('Start Your Home Kitchen Today'), findsNothing);
    expect(find.text('Become the First Chef'), findsNothing);
  });

  testWidgets('a new signup keeps the cook invite over a stale seller role',
      (tester) async {
    addTearDown(SessionService.clear);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'society_id': 'society-1',
      'user_role': 'seller',
      'auth_token': 'test-token',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
          onStartSelling: () {},
          readProfile: () async => {'id': 'buyer-1', 'role': 'buyer'},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Why Cook on SocietyEats?'), findsOneWidget);
    expect(find.text('Start Your Home Kitchen Today'), findsOneWidget);
    expect(find.text('Become the First Chef'), findsOneWidget);
  });

  testWidgets('a seller with no products still sees the cook invite',
      (tester) async {
    addTearDown(SessionService.clear);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'society_id': 'society-1',
      'user_role': 'seller',
      'auth_token': 'test-token',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
          onStartSelling: () {},
          readProfile: () async => {'id': 'seller-1', 'role': 'seller'},
          readOwnListings: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Why Cook on SocietyEats?'), findsOneWidget);
    expect(find.text('Start Your Home Kitchen Today'), findsOneWidget);
    expect(find.text('Become the First Chef'), findsOneWidget);
  });

  test('chef hunt message names the site and the Android app', () {
    expect(
      chefHuntInviteMessage(wingLabel: 'Wing B', societyName: 'Green Valley'),
      'Hello,\n\n'
      'SocietyEats is looking for a home chef in our society or neighbourhood. '
      'Nominate a home chef, or join yourself. '
      'SocietyEats will help you get your first order and provide full assistance with setup.\n\n'
      'Website: https://www.societyeats.com\n'
      'Android app: https://play.google.com/store/apps/details?id=com.puran.societybites\n'
      'iOS: Coming soon',
    );
    expect(chefHuntWingLabel('B'), 'Wing B');
    expect(chefHuntEyebrow, 'COMMUNITY CHEF HUNT');
  });

  testWidgets('a signed-in discovery home shows the wing hunt', (tester) async {
    addTearDown(SessionService.clear);
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'society_id': 'society-1'});
    await SessionService.saveToken('test-token');
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
          readProfile: () async => {
            'id': 'buyer-1',
            'role': 'buyer',
            'flat': {'block': 'B'},
            'society': {'name': 'Green Valley'},
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('COMMUNITY CHEF HUNT'), findsOneWidget);
    expect(find.textContaining('in your society or outside'), findsOneWidget);
    expect(find.textContaining('food wallet'), findsNothing);
  });

  testWidgets('a signed-in resident sees the chef hunt at the bottom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryHome(
          nearbyListings: const [],
          showChefHunt: true,
          chefWing: 'Wing B',
          chefSocietyName: 'Green Valley',
          onChefHuntInvite: (message) async => sent = message,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('COMMUNITY CHEF HUNT'), findsOneWidget);
    expect(find.text('Invite via WhatsApp'), findsOneWidget);
    expect(find.textContaining('food wallet'), findsNothing);
    final hunt = tester.getTopLeft(find.text('COMMUNITY CHEF HUNT'));
    final cook = tester.getTopLeft(find.text('Why Cook on SocietyEats?'));
    expect(hunt.dy, greaterThan(cook.dy));

    await tester.ensureVisible(find.text('Invite via WhatsApp'));
    await tester.tap(find.text('Invite via WhatsApp'));
    await tester.pump();
    expect(sent, chefHuntInviteMessage(wingLabel: 'Wing B', societyName: 'Green Valley'));
  });

  testWidgets('an active feed keeps the existing home screen', (tester) async {
    SharedPreferences.setMockInitialValues({'society_id': 'society-1'});
    final listings = <Map<String, dynamic>>[];
    for (var seller = 1; seller <= 5; seller++) {
      for (var dish = 1; dish <= 4; dish++) {
        listings.add({
          'id': 's$seller-d$dish',
          'name': 'Dish $seller $dish',
          'sellerId': 'seller-$seller',
          'sellerName': 'Seller $seller',
          'price': 80,
          'status': 'active',
          'quantity': 4,
          'catalogType': 'REGULAR',
          'availabilityMode': 'READY_NOW',
          'foodType': 'VEG',
          'category': 'Snacks',
          'societyId': 'society-1',
        });
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => listings,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Homemade Food is Coming to Your Society'), findsNothing);
    expect(find.text('Growing marketplace'), findsNothing);
    expect(find.text('Dish 1 1'), findsOneWidget);
  });

  testWidgets('a small feed keeps the existing home screen', (tester) async {
    SharedPreferences.setMockInitialValues({'society_id': 'society-1'});
    final listings = <Map<String, dynamic>>[];
    for (var seller = 1; seller <= 2; seller++) {
      for (var dish = 1; dish <= 4; dish++) {
        listings.add({
          'id': 'g$seller-d$dish',
          'name': 'Growing $seller $dish',
          'sellerId': 'seller-$seller',
          'sellerName': 'Seller $seller',
          'price': 80,
          'status': 'active',
          'quantity': 4,
          'catalogType': 'REGULAR',
          'availabilityMode': 'READY_NOW',
          'foodType': 'VEG',
          'category': 'Snacks',
          'societyId': 'society-1',
        });
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => listings,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Growing marketplace'), findsNothing);
    expect(find.text('This screen will be designed later.'), findsNothing);
    expect(find.text('Growing 1 1'), findsOneWidget);
  });

  testWidgets('eligible nearby dishes keep the existing home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'society_id': 'society-1'});
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
          fetchNearbySellers: () async => {
            'available': true,
            'extendedRadiusKm': 10,
            'nearbyRadiusKm': 5,
            'sellers': [
              {
                'distanceKm': 3,
                'societyName': 'Nearby Homes',
                'seller': {
                  'sellingReachLevel': 'BEYOND_SOCIETY',
                  'distanceKm': 3,
                  'societyName': 'Nearby Homes',
                },
                'listings': [
                  {
                    'id': 'nearby-dosa',
                    'name': 'Neighbour Dosa',
                    'sellerId': 'seller-near',
                    'sellerName': 'Lakshmi',
                    'price': 60,
                    'status': 'active',
                    'quantity': 4,
                    'catalogType': 'REGULAR',
                    'availabilityMode': 'READY_NOW',
                    'societyId': 'society-2',
                    'distanceKm': 3,
                    'sellingReachLevel': 'BEYOND_SOCIETY',
                  },
                ],
              },
            ],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Homemade Food is Coming to Your Society'), findsNothing);
    expect(find.text('Ordering today from nearby societies'), findsNothing);
    expect(find.text('Neighbour Dosa'), findsWidgets);
    expect(find.text('Lakshmi'), findsWidgets);
  });

  testWidgets('a failed nearby load keeps Discovery and hides the nearby section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'society_id': 'society-1'});
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
          fetchNearbySellers: () async => throw Exception('nearby down'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Homemade Food is Coming to Your Society'), findsOneWidget);
    expect(find.text('Ordering today from nearby societies'), findsNothing);
    expect(find.text('What neighbours love to cook'), findsOneWidget);
  });

  testWidgets('ineligible nearby dishes stay on the discovery screen without a nearby section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'society_id': 'society-1'});
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(
          homeKey: GlobalKey<HomeScreenState>(),
          fetchListings: () async => const [],
          fetchNearbySellers: () async => {
            'available': true,
            'extendedRadiusKm': 10,
            'nearbyRadiusKm': 5,
            'sellers': [
              {
                'distanceKm': 3,
                'seller': {
                  'sellingReachLevel': 'BEYOND_SOCIETY',
                  'distanceKm': 3,
                },
                'listings': [
                  {
                    'id': 'expired-dish',
                    'name': 'Expired Dish',
                    'sellerId': 'seller-near',
                    'sellerName': 'Lakshmi',
                    'price': 60,
                    'status': 'expired',
                    'quantity': 4,
                    'catalogType': 'REGULAR',
                    'availabilityMode': 'READY_NOW',
                    'societyId': 'society-2',
                    'distanceKm': 3,
                    'sellingReachLevel': 'BEYOND_SOCIETY',
                  },
                ],
              },
            ],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Homemade Food is Coming to Your Society'), findsOneWidget);
    expect(find.text('Expired Dish'), findsNothing);
    expect(find.text('Ordering today from nearby societies'), findsNothing);
  });

  testWidgets('seller CTA uses the existing callback and invite stays unwired', (
    tester,
  ) async {
    var started = false;
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryHome(
          nearbyListings: const [],
          onStartSelling: () => started = true,
        ),
      ),
    );
    await tester.tap(find.text('Start Your Home Kitchen Today'));
    await tester.pump();
    expect(started, isTrue);
    expect(find.text('Invite neighbours'), findsNothing);
    expect(find.text('Become the First Chef'), findsOneWidget);
  });

  testWidgets('a rebuilt discovery cover returns after the home screen is kept', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'society_id': 'society-1'});
    final homeKey = GlobalKey<HomeScreenState>();
    Future<List<Map<String, dynamic>>> listings() async => const [];

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(homeKey: homeKey, fetchListings: listings),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Homemade Food is Coming to Your Society'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHome(homeKey: homeKey, fetchListings: listings),
      ),
    );
    await tester.pump();

    expect(find.text('Homemade Food is Coming to Your Society'), findsOneWidget);
    expect(find.text('Fresh flavors from'), findsNothing);
  });

  testWidgets('categories do not navigate', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: DiscoveryHome(nearbyListings: []),
      ),
    );
    await tester.tap(find.text('Breakfast & Brunch'));
    await tester.pump();
    expect(find.text('Breakfast & Brunch'), findsOneWidget);
    expect(find.byType(DiscoveryHome), findsOneWidget);
  });

  testWidgets('overflowing rows offer a chevron instead of a hard cut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryHome(
          nearbyListings: [
            for (var i = 0; i < 6; i++)
              _food('Dish $i', 'Seller $i', societyId: 'society-2', distanceKm: 3),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Show more'), findsNWidgets(2));
    expect(find.byTooltip('Show previous'), findsNothing);

    await tester.tap(find.byTooltip('Show more').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Show previous'), findsOneWidget);
  });
}
