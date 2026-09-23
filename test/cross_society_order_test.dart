import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/nearby_seller.dart';
import 'package:societybites/models/seller_fulfilment.dart';
import 'package:societybites/screens/checkout_screen.dart';
import 'package:societybites/screens/home_screen.dart';
import 'package:societybites/screens/orders_screen.dart';
import 'package:societybites/screens/seller_storefront_screen.dart';
import 'package:societybites/widgets/order_fulfilment_banner.dart';

FoodItem _food({
  required String id,
  required String sellerId,
  required String sellerName,
  String name = 'Paneer',
  String societyId = 'society-b',
}) {
  return FoodItem.fromJson({
    'id': id,
    'name': name,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'price': 80,
    'quantity': 4,
    'status': 'active',
    'societyId': societyId,
  });
}

CartItem _cartItem(FoodItem food) => CartItem(food: food, quantity: 1);

NearbySellerCard _card({
  required String mode,
  double? charge,
}) {
  return NearbySellerCard.fromJson({
    'seller': {
      'id': 'seller-b',
      'name': "Anita's Kitchen",
      'societyName': 'Prestige Shantiniketan',
      'distanceKm': 3.2,
    },
    'fulfilment': {'mode': mode, 'deliveryCharge': charge},
    'listings': [
      {
        'id': 'listing-1',
        'name': 'Jeera Rice',
        'sellerId': 'seller-b',
        'sellerName': "Anita's Kitchen",
        'price': 80,
        'quantity': 4,
        'status': 'active',
      },
    ],
  });
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SellerStorefrontMemoryCache.clear();
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'society_id': 'society-a',
    });
  });

  testWidgets('Nearby seller can add item to cart', (tester) async {
    final card = _card(mode: 'BOTH', charge: 30);
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          seller: const Seller(
            id: 'seller-b',
            name: "Anita's Kitchen",
            block: 'A',
            rating: 0,
            avatarIcon: Icons.restaurant,
            avatarColor: Color(0xFFE8F5EE),
          ),
          nearbyContext: card,
          initialProducts: card.listings,
          fetchListings: () async => [
            {
              'id': 'listing-1',
              'name': 'Jeera Rice',
              'sellerId': 'seller-b',
              'sellerName': "Anita's Kitchen",
              'price': 80,
              'quantity': 4,
              'status': 'active',
            },
          ],
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Nearby seller'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.textContaining('items'), findsWidgets);
  });

  testWidgets('different seller triggers one-seller cart protection', (
    tester,
  ) async {
    final first = _food(id: 'a', sellerId: 's1', sellerName: 'Cook A');
    final second = _food(id: 'b', sellerId: 's2', sellerName: 'Cook B');
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          seller: const Seller(
            id: 's1',
            name: 'Cook A',
            block: 'A',
            rating: 0,
            avatarIcon: Icons.restaurant,
            avatarColor: Color(0xFFE8F5EE),
          ),
          cartItems: [_cartItem(first)],
          fetchListings: () async => [
            {
              'id': 'b',
              'name': 'Dal',
              'sellerId': 's2',
              'sellerName': 'Cook B',
              'price': 80,
              'quantity': 4,
              'status': 'active',
            },
          ],
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your cart contains items from another seller.'),
      findsOneWidget,
    );
    expect(find.text('Start New Cart'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('pickup-only seller shows pickup at checkout', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            _cartItem(_food(id: '1', sellerId: 's', sellerName: 'Anita')),
          ],
          isCrossSociety: true,
          sellerFulfilment: const SellerFulfilment(
            mode: FulfilmentMode.buyerPickup,
          ),
          sellerSocietyName: 'Prestige Shantiniketan',
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async =>
              {'id': 'o1'},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('🏠 Buyer Pickup'), findsOneWidget);
    expect(find.textContaining("seller's society"), findsOneWidget);
    expect(find.text('🛵 Seller Delivery'), findsNothing);
  });

  testWidgets('delivery-only seller shows delivery charge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            _cartItem(_food(id: '1', sellerId: 's', sellerName: 'Anita')),
          ],
          isCrossSociety: true,
          sellerFulfilment: const SellerFulfilment(
            mode: FulfilmentMode.sellerDelivery,
            deliveryCharge: 30,
          ),
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async =>
              {'id': 'o1'},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('🛵 Seller Delivery'), findsOneWidget);
    expect(find.textContaining('₹30'), findsWidgets);
    expect(find.text('🏠 Buyer Pickup'), findsNothing);
  });

  testWidgets('BOTH seller shows both options', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            _cartItem(_food(id: '1', sellerId: 's', sellerName: 'Anita')),
          ],
          isCrossSociety: true,
          sellerFulfilment: const SellerFulfilment(
            mode: FulfilmentMode.both,
            deliveryCharge: 40,
          ),
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async =>
              {'id': 'o1'},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('🏠 Buyer Pickup'), findsOneWidget);
    expect(find.text('🛵 Seller Delivery'), findsOneWidget);
  });

  testWidgets('checkout infers nearby order from listing societyId', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            CartItem(
              food: FoodItem.fromJson({
                'id': 'sushi',
                'name': 'veg Sushi',
                'sellerId': 'aarav',
                'sellerName': 'Aarav',
                'price': 80,
                'quantity': 4,
                'status': 'active',
                'societyId': 'society-b',
                'fulfilmentMode': 'BOTH',
                'deliveryCharge': 30,
              }),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Delivery mechanism'), findsOneWidget);
    expect(find.text("As per the seller's preference"), findsOneWidget);
    expect(find.text('🏠 Buyer Pickup'), findsOneWidget);
    expect(find.text('🛵 Seller Delivery'), findsOneWidget);
  });

  testWidgets('cross-society checkout sends selected fulfilment', (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            _cartItem(_food(id: '1', sellerId: 's', sellerName: 'Anita')),
          ],
          isCrossSociety: true,
          sellerFulfilment: const SellerFulfilment(
            mode: FulfilmentMode.sellerDelivery,
            deliveryCharge: 30,
          ),
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async {
            sent = fulfilmentMethod;
            return {'id': 'o1'};
          },
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('confirm-order')));
    await tester.tap(find.byKey(const Key('confirm-order')));
    await tester.pump();
    await tester.pump();
    expect(sent, 'seller_delivery');
  });

  testWidgets('backend rejection is shown cleanly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            _cartItem(_food(id: '1', sellerId: 's', sellerName: 'Anita')),
          ],
          isCrossSociety: true,
          sellerFulfilment: const SellerFulfilment(
            mode: FulfilmentMode.buyerPickup,
          ),
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async {
            throw Exception(
              'This seller is no longer available for delivery to your society.',
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('confirm-order')));
    await tester.tap(find.byKey(const Key('confirm-order')));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('This seller is no longer available in your area.'),
      findsOneWidget,
    );
  });

  testWidgets('same-society checkout has no nearby fulfilment picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            _cartItem(_food(
              id: '1',
              sellerId: 's',
              sellerName: 'Anita',
              societyId: 'society-a',
            )),
          ],
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async =>
              {'id': 'o1'},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('🏠 Buyer Pickup'), findsNothing);
    expect(find.text('🛵 Seller Delivery'), findsNothing);
    expect(find.text('Review your\ncommunity order'), findsOneWidget);
  });

  testWidgets('buyer order shows fulfilment responsibility', (tester) async {
    final order = Order.fromJson({
      'id': 'o1',
      'orderNumber': 'SB-1',
      'status': 'accepted',
      'total': 110,
      'subtotal': 80,
      'fulfilmentMethod': 'seller_delivery',
      'deliveryCharge': 30,
      'sellerSocietyName': 'Prestige Shantiniketan',
      'items': [
        {
          'quantity': 1,
          'unitPrice': 80,
          'listing': {
            'id': 'l1',
            'name': 'Rice',
            'sellerId': 's',
            'sellerName': "Anita's Kitchen",
            'price': 80,
          },
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderFulfilmentBanner(order: order, isSellerView: false),
        ),
      ),
    );
    expect(find.text('🛵 SELLER DELIVERY'), findsOneWidget);
    expect(find.text('Seller will deliver your order.'), findsOneWidget);
    expect(find.text('Delivery charge: ₹30'), findsOneWidget);
  });

  testWidgets('Home with listings still shows society marketplace', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            {
              'id': 'listing-home',
              'name': 'Society Dal',
              'sellerId': 'seller-1',
              'sellerName': 'Anita',
              'price': 100,
              'status': 'active',
            },
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Society Dal'), findsOneWidget);
    expect(find.text('No sellers available in your society yet'), findsNothing);
  });

  testWidgets('Orders behavior still shows buyer orders', (tester) async {
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
    expect(find.text('Buyer Biryani'), findsOneWidget);
  });
}
