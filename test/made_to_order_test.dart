import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/screens/add_listing_screen.dart';
import 'package:societybites/screens/checkout_screen.dart';
import 'package:societybites/widgets/order_timing_notice.dart';
import 'package:societybites/screens/food_detail_screen.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/screens/my_listings_screen.dart';
import 'package:societybites/screens/seller_storefront_screen.dart';
import 'package:societybites/services/my_listings_cache.dart';
import 'package:societybites/widgets/made_to_order_hint.dart';
import 'package:societybites/widgets/one_seller_cart.dart';

Map<String, dynamic> _listingJson(
  String name, {
  String catalogType = listingCatalogRegular,
  String availabilityMode = listingAvailabilityReadyNow,
  int? preparationTimeMinutes,
  String id = '',
  String? foodType = 'VEG',
  String category = 'Snacks',
}) {
  return {
    'id': id.isEmpty ? 'listing-$name' : id,
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 100,
    'status': 'active',
    'catalogType': catalogType,
    'availabilityMode': availabilityMode,
    'preparationTimeMinutes': preparationTimeMinutes,
    'foodType': foodType,
    'category': category,
    'quantity': 5,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MyListingsCache.clear();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_name': 'Anita',
      'phone': '9999999999',
      'society_name': 'Green Heights',
    });
  });

  Future<void> _openAddListing(
    WidgetTester tester, {
    String availabilityMode = listingAvailabilityReadyNow,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AddListingScreen(initialAvailabilityMode: availabilityMode),
      ),
    );
    await tester.pump();
  }

  testWidgets('Add Listing does not ask fulfilment again after type is chosen', (
    tester,
  ) async {
    await _openAddListing(tester);

    expect(find.text('HOW WILL YOU FULFIL THIS?'), findsNothing);
    expect(find.text('Available now order'), findsOneWidget);
    expect(find.text('Made to Order'), findsNothing);
    expect(find.text('PREPARATION TIME'), findsNothing);
  });

  testWidgets('Made to Order form shows preparation-time controls', (
    tester,
  ) async {
    await _openAddListing(
      tester,
      availabilityMode: listingAvailabilityMadeToOrder,
    );

    expect(find.text('HOW WILL YOU FULFIL THIS?'), findsNothing);
    expect(find.text('Made to order'), findsOneWidget);
    expect(find.text('PREPARATION TIME'), findsOneWidget);
    expect(find.text('QUANTITY AVAILABLE'), findsNothing);
    expect(find.text('DATE/TIME AVAILABLE UNTIL'), findsNothing);
    expect(find.text('MAXIMUM ORDERS PER DAY (OPTIONAL)'), findsNothing);
  });

  test('day-based preparation estimates format correctly', () {
    expect(preparationMinutesFromDays(2), 2880);
    expect(preparationDaysFromMinutes(1440), 1);
    expect(preparationDaysFromMinutes(240), isNull);
    expect(formatPreparationEstimate(1440), 'Usually takes about 1 day');
    expect(formatPreparationEstimate(2880), 'Usually takes about 2 days');
    expect(formatPreparationShort(1440), '~1 day');
    expect(formatPreparationEstimate(240), 'Usually takes about 4 hours');
  });

  testWidgets('Made to Order days field accepts numbers only and validates range', (
    tester,
  ) async {
    await _openAddListing(
      tester,
      availabilityMode: listingAvailabilityMadeToOrder,
    );

    final daysField = find.byKey(const Key('prep-days-field'));
    expect(daysField, findsOneWidget);

    await tester.enterText(daysField, 'ab12cd');
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: daysField, matching: find.byType(TextField)),
          )
          .controller
          ?.text,
      '12',
    );

    await tester.enterText(daysField, '0');
    await tester.ensureVisible(find.text('List Item'));
    await tester.tap(find.text('List Item'));
    await tester.pump();
    expect(find.text('1–7'), findsOneWidget);

    await tester.enterText(daysField, '8');
    await tester.ensureVisible(find.text('List Item'));
    await tester.tap(find.text('List Item'));
    await tester.pump();
    expect(find.text('1–7'), findsOneWidget);
  });

  testWidgets('editing can switch from Made to Order back to Ready Now', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AddListingScreen(
          existingListing: FoodItem(
            id: 'l1',
            name: 'Cake',
            sellerId: 's1',
            sellerName: 'Anita',
            block: 'A',
            price: 250,
            rating: 5,
            pickupTime: '5 PM',
            description: '',
            icon: Icons.cake,
            bgColor: const Color(0xFFE8F5EE),
            availabilityMode: listingAvailabilityMadeToOrder,
            preparationTimeMinutes: 60,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('PREPARATION TIME'), findsOneWidget);

    await tester.tap(find.text('Available Now'));
    await tester.pump();
    expect(find.text('PREPARATION TIME'), findsNothing);
  });

  testWidgets('Pre-order add listing hides fulfilment controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AddListingScreen(catalogType: listingCatalogPreorder),
      ),
    );
    await tester.pump();
    expect(find.textContaining('HOW WILL YOU FULFIL THIS?'), findsNothing);
    expect(find.text('Available Now'), findsNothing);
    expect(find.text('QUANTITY AVAILABLE'), findsNothing);
    expect(find.text('DATE/TIME AVAILABLE UNTIL'), findsNothing);
  });

  testWidgets('My Kitchen filters Made to Order separately', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [
            _listingJson('Dhokla'),
            _listingJson(
              'Chocolate Cake',
              availabilityMode: listingAvailabilityMadeToOrder,
              preparationTimeMinutes: 240,
              category: 'Desserts',
            ),
            _listingJson(
              'Diwali Box',
              catalogType: listingCatalogPreorder,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Dhokla'), findsOneWidget);
    expect(find.text('Chocolate Cake'), findsOneWidget);
    expect(find.text('Diwali Box'), findsOneWidget);

    await tester.tap(find.textContaining('Made to Order (').first);
    await tester.pumpAndSettle();
    expect(find.text('Chocolate Cake'), findsOneWidget);
    expect(find.text('Dhokla'), findsNothing);
    expect(find.text('MADE TO ORDER'), findsWidgets);

    await tester.tap(find.textContaining('Regular (').first);
    await tester.pumpAndSettle();
    expect(find.text('Dhokla'), findsOneWidget);
    expect(find.text('Chocolate Cake'), findsNothing);
    expect(find.text('REGULAR'), findsWidgets);
  });

  testWidgets('buyer storefront displays Made to Order hint', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          seller: const Seller(
            id: 'seller-1',
            name: 'Anita',
            block: 'Block A',
            rating: 4.8,
            avatarIcon: Icons.person,
            avatarColor: Color(0xFF0E5A47),
          ),
          fetchListings: () async => [
            _listingJson(
              'Chocolate Cake',
              availabilityMode: listingAvailabilityMadeToOrder,
              preparationTimeMinutes: 240,
              category: 'Desserts',
            ),
          ],
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Chocolate Cake'), findsOneWidget);
    expect(find.text('MADE TO ORDER'), findsWidgets);
    expect(find.byType(MadeToOrderHint), findsWidgets);
    expect(find.textContaining('Made to Order'), findsWidgets);
  });

  testWidgets('food detail shows Made to Order copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodDetailScreen(
          food: FoodItem.fromJson(
            _listingJson(
              'Chocolate Cake',
              availabilityMode: listingAvailabilityMadeToOrder,
              preparationTimeMinutes: 240,
              category: 'Desserts',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('MADE TO ORDER'), findsWidgets);
    expect(find.textContaining('Made to Order'), findsWidgets);
    expect(find.textContaining('Seller confirms availability'), findsWidgets);
  });

  test('Home category and veg filters still include Made to Order', () {
    final listings = [
      FoodItem.fromJson(
        _listingJson(
          'Chocolate Cake',
          availabilityMode: listingAvailabilityMadeToOrder,
          preparationTimeMinutes: 240,
          category: 'Desserts',
        ),
      ),
      FoodItem.fromJson(
        _listingJson('Chicken', foodType: 'NON_VEG', category: 'Dinner'),
      ),
      FoodItem.fromJson(
        _listingJson(
          'Diwali Box',
          catalogType: listingCatalogPreorder,
          category: 'Desserts',
        ),
      ),
    ];

    final filtered = applyHomeListingFilters(
      listings,
      category: 'Desserts',
      foodType: 'VEG',
    );
    expect(filtered.map((item) => item.name), ['Chocolate Cake']);
  });

  test('existing Regular listing stays READY_NOW', () {
    final food = FoodItem.fromJson(_listingJson('Samosa'));
    expect(food.isMadeToOrder, isFalse);
    expect(food.availabilityMode, listingAvailabilityReadyNow);
    expect(food.isPreOrderCatalog, isFalse);
  });

  test('cart rejects mixing Available now and Made to order', () {
    final ready = FoodItem.fromJson(_listingJson('Samosa'));
    final made = FoodItem.fromJson(
      _listingJson(
        'Cake',
        availabilityMode: listingAvailabilityMadeToOrder,
        preparationTimeMinutes: 120,
      ),
    );
    final otherReady = FoodItem.fromJson(_listingJson('Pakora'));
    final otherMade = FoodItem.fromJson(
      _listingJson(
        'Cookies',
        availabilityMode: listingAvailabilityMadeToOrder,
        preparationTimeMinutes: 60,
      ),
    );

    expect(
      cartAvailabilityConflict([CartItem(food: ready)], made),
      mixedAvailabilityCartMessage,
    );
    expect(
      cartAvailabilityConflict([CartItem(food: made)], ready),
      mixedAvailabilityCartMessage,
    );
    expect(cartAvailabilityConflict([CartItem(food: ready)], otherReady), isNull);
    expect(
      cartAvailabilityConflict([CartItem(food: made)], otherMade),
      multipleMadeToOrderCartMessage,
    );
    expect(cartAvailabilityConflict([CartItem(food: ready)], ready), isNull);
    expect(cartHasMixedAvailability([CartItem(food: ready), CartItem(food: made)]), isTrue);
  });

  testWidgets('storefront shows mix message instead of adding', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SellerStorefrontMemoryCache.clear();
    final ready = FoodItem.fromJson(_listingJson('Samosa', id: 'ready-1'));
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          seller: const Seller(
            id: 'seller-1',
            name: 'Anita',
            block: 'A',
            rating: 0,
            avatarIcon: Icons.restaurant,
            avatarColor: Color(0xFFE8F5EE),
          ),
          cartItems: [CartItem(food: ready)],
          fetchListings: () async => [
            _listingJson(
              'Cake',
              id: 'mto-1',
              availabilityMode: listingAvailabilityMadeToOrder,
              preparationTimeMinutes: 120,
            ),
          ],
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text(mixedAvailabilityCartMessage), findsOneWidget);
    expect(find.text('Cake'), findsOneWidget);
  });

  testWidgets('checkout explains Made to Order timeline', (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = '${details.exception}\n${details.summary}';
      if (text.contains('A RenderFlex overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            CartItem(
              food: FoodItem.fromJson(
                _listingJson(
                  'Birthday Cakes',
                  availabilityMode: listingAvailabilityMadeToOrder,
                  preparationTimeMinutes: 240,
                  category: 'Desserts',
                ),
              ),
              quantity: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(OrderTimingNotice), findsOneWidget);
    expect(find.text('This is not a regular ready-now order'), findsOneWidget);
    expect(find.textContaining('Usually takes about 4 hours'), findsWidgets);
    expect(find.text('How would you like to receive your order?'), findsNothing);
  });
}
