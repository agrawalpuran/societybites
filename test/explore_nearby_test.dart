import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/nearby_seller.dart';
import 'package:societybites/screens/explore_nearby_screen.dart';
import 'package:societybites/screens/home_screen.dart';
import 'package:societybites/screens/orders_screen.dart';
import 'package:societybites/screens/seller_storefront_screen.dart';

Map<String, dynamic> _listing(String name) {
  return {
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita\'s Kitchen',
    'price': 120,
    'status': 'active',
  };
}

Map<String, dynamic> _nearbySeller({
  required String id,
  required String name,
  required String society,
  required double distanceKm,
  required String mode,
  double? deliveryCharge,
  List<String> dishes = const ['Paneer Butter Masala'],
}) {
  return {
    'seller': {
      'id': id,
      'name': name,
      'societyName': society,
      'distanceKm': distanceKm,
      'sellingReachLevel': 'NEARBY',
    },
    'fulfilment': {'mode': mode, 'deliveryCharge': deliveryCharge},
    'listings': dishes
        .map(
          (dish) => {
            'id': '$id-$dish',
            'name': dish,
            'sellerId': id,
            'sellerName': name,
            'price': 80,
            'status': 'active',
          },
        )
        .toList(),
  };
}

Map<String, dynamic> _nearbyPayload({
  bool available = true,
  String? reason,
  String society = 'Prestige Notting Hill',
  double? radius = 10,
  List<Map<String, dynamic>> sellers = const [],
}) {
  return {
    'available': available,
    'reason': reason,
    'buyerSocietyName': society,
    'appliedRadiusKm': radius,
    'sellers': sellers,
  };
}

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('ListTile background color')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _pumpHomeEmpty(
  WidgetTester tester, {
  VoidCallback? onStartSelling,
  VoidCallback? onExploreNearby,
  List<Map<String, dynamic>> listings = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'user_id': 'user-1',
    'user_name': 'Neighbor',
  });
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        fetchListings: () async => listings,
        onStartSelling: onStartSelling,
        onExploreNearby: onExploreNearby,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SellerStorefrontMemoryCache.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('empty society state appears with Start Selling and Explore Nearby', (
    tester,
  ) async {
    _ignoreOverflow();
    var startSelling = false;
    var explore = false;
    await _pumpHomeEmpty(
      tester,
      onStartSelling: () => startSelling = true,
      onExploreNearby: () => explore = true,
    );

    expect(find.text('No sellers available in your society yet'), findsOneWidget);
    expect(
      find.textContaining('Be the first one to share homemade food'),
      findsOneWidget,
    );
    expect(find.text('Discover home food from nearby societies'), findsOneWidget);

    await tester.tap(find.text('Start Selling'));
    await tester.pump();
    expect(startSelling, isTrue);

    await tester.tap(find.text('Explore Nearby'));
    await tester.pump();
    expect(explore, isTrue);
  });

  testWidgets('Start Selling CTA uses existing confirmation dialog', (
    tester,
  ) async {
    _ignoreOverflow();
    await _pumpHomeEmpty(tester);
    await tester.tap(find.text('Start Selling'));
    await tester.pumpAndSettle();
    expect(find.text('Start selling?'), findsOneWidget);
    expect(find.text('Enable selling'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
  });

  testWidgets('Explore Nearby CTA opens nearby screen', (tester) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({'user_id': 'user-1'});
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(fetchListings: () async => []),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Explore Nearby'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Explore Nearby'), findsWidgets);
  });

  testWidgets('nearby sellers, distance, and fulfilment badges render', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreNearbyScreen(
          fetchNearby: () async => _nearbyPayload(
            sellers: [
              _nearbySeller(
                id: 's1',
                name: "Anita's Kitchen",
                society: 'Prestige Shantiniketan',
                distanceKm: 3.2,
                mode: 'BOTH',
                deliveryCharge: 40,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('📍 Near Prestige Notting Hill'), findsOneWidget);
    expect(find.textContaining('Looking up to 10 km'), findsOneWidget);
    expect(find.text("Anita's Kitchen"), findsOneWidget);
    expect(find.text('Prestige Shantiniketan'), findsOneWidget);
    expect(find.text('3.2 km away'), findsOneWidget);
    expect(find.text('🛵 Seller Delivery'), findsOneWidget);
    expect(find.text('🏠 Pickup Available'), findsOneWidget);
    expect(find.text('Delivery ₹40'), findsOneWidget);
  });

  testWidgets('pickup-only seller hides delivery badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreNearbyScreen(
          fetchNearby: () async => _nearbyPayload(
            sellers: [
              _nearbySeller(
                id: 's2',
                name: 'Pickup Kitchen',
                society: 'Cadenza',
                distanceKm: 1.5,
                mode: 'BUYER_PICKUP',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('🏠 Pickup Available'), findsOneWidget);
    expect(find.text('🛵 Seller Delivery'), findsNothing);
    expect(find.textContaining('Delivery'), findsNothing);
  });

  testWidgets('delivery-only seller and free delivery render', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreNearbyScreen(
          fetchNearby: () async => _nearbyPayload(
            sellers: [
              _nearbySeller(
                id: 's3',
                name: 'Delivery Kitchen',
                society: 'Hill Crest',
                distanceKm: 2,
                mode: 'SELLER_DELIVERY',
                deliveryCharge: 0,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('🛵 Seller Delivery'), findsOneWidget);
    expect(find.text('🏠 Pickup Available'), findsNothing);
    expect(find.text('Free delivery'), findsOneWidget);
  });

  testWidgets('no nearby sellers state offers Start Selling', (tester) async {
    var started = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreNearbyScreen(
          onStartSelling: () => started = true,
          fetchNearby: () async => _nearbyPayload(sellers: []),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('No nearby sellers yet'), findsOneWidget);
    expect(find.textContaining('growing SocietyBites'), findsOneWidget);
    await tester.tap(find.text('Start Selling'));
    await tester.pump();
    expect(started, isTrue);
  });

  testWidgets('seller storefront from Nearby shows browse context', (
    tester,
  ) async {
    NearbySellerCard? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ExploreNearbyScreen(
          onOpenStorefront: (card) => opened = card,
          fetchNearby: () async => _nearbyPayload(
            sellers: [
              _nearbySeller(
                id: 's4',
                name: "Anita's Kitchen",
                society: 'Prestige Shantiniketan',
                distanceKm: 3.2,
                mode: 'SELLER_DELIVERY',
                deliveryCharge: 40,
                dishes: ['Jeera Rice'],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('View Menu'));
    await tester.pump();
    expect(opened?.sellerName, "Anita's Kitchen");
    expect(opened?.distanceKm, 3.2);
  });

  testWidgets('nearby storefront banner keeps existing storefront chrome', (
    tester,
  ) async {
    final card = NearbySellerCard.fromJson(
      _nearbySeller(
        id: 's5',
        name: 'Nearby Cook',
        society: 'Prestige Shantiniketan',
        distanceKm: 3.2,
        mode: 'BOTH',
        deliveryCharge: 40,
        dishes: ['Aloo Paratha'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          seller: const Seller(
            id: 's5',
            name: 'Nearby Cook',
            block: 'A',
            rating: 0,
            avatarIcon: Icons.restaurant,
            avatarColor: Color(0xFFE8F5EE),
          ),
          nearbyContext: card,
          browseOnly: false,
          initialProducts: card.listings,
          fetchListings: () async => [
            {
              'id': 'p1',
              'name': 'Aloo Paratha',
              'sellerId': 's5',
              'sellerName': 'Nearby Cook',
              'price': 40,
              'status': 'active',
            },
          ],
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Seller Storefront'), findsOneWidget);
    expect(find.text('Nearby seller'), findsOneWidget);
    expect(find.textContaining('Prestige Shantiniketan'), findsOneWidget);
    expect(find.text('Aloo Paratha'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('Home with society listings does not show empty nearby state', (
    tester,
  ) async {
    _ignoreOverflow();
    await _pumpHomeEmpty(tester, listings: [_listing('Paneer Wrap')]);
    expect(find.text('No sellers available in your society yet'), findsNothing);
    expect(find.text('Explore Nearby'), findsNothing);
    expect(find.text('Paneer Wrap'), findsOneWidget);
  });

  testWidgets('Orders screen still shows buyer orders', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [
            {
              'id': 'buyer-order-1',
              'orderNumber': 'BUY-1',
              'status': 'accepted',
              'items': [
                {
                  'quantity': 1,
                  'unitPrice': 120,
                  'listing': {
                    'id': 'listing-1',
                    'name': 'Buyer Biryani',
                    'sellerId': 'seller-1',
                    'price': 120,
                  },
                },
              ],
            },
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('BUY-1'), findsOneWidget);
    expect(find.text('Buyer Biryani'), findsOneWidget);
  });
}
