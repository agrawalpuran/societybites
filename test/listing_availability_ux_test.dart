import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/food_type.dart';
import 'package:societybites/screens/food_detail_screen.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/screens/home_screen.dart';
import 'package:societybites/screens/my_listings_screen.dart';
import 'package:societybites/services/my_listings_cache.dart';
import 'package:societybites/widgets/listing_purchase_slot.dart';

Map<String, dynamic> _listingJson({
  required String name,
  String status = 'active',
  String foodType = 'VEG',
  String category = 'Lunch',
  String catalogType = listingCatalogRegular,
  int quantity = 5,
}) {
  return {
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Puran Agrawal',
    'price': 175,
    'status': status,
    'foodType': foodType,
    'category': category,
    'catalogType': catalogType,
    'quantity': quantity,
    'description': 'Home cooked',
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('expired listings are discoverable in client filters but not orderable', () {
    final expired = FoodItem.fromJson(_listingJson(
      name: 'Chicken Biryani',
      status: 'expired',
      foodType: 'NON_VEG',
    ));
    final vegActive = FoodItem.fromJson(_listingJson(name: 'Dal'));
    final paused = FoodItem.fromJson(_listingJson(name: 'Hidden', status: 'paused'));
    final preorder = FoodItem.fromJson(
      _listingJson(name: 'Sunday Thali', catalogType: listingCatalogPreorder),
    );

    expect(expired.isExpired, isTrue);
    expect(expired.canAddToCart, isFalse);
    expect(vegActive.canAddToCart, isTrue);

    final filtered = applyHomeListingFilters(
      [expired, vegActive, preorder],
      foodType: foodTypeVeg,
      category: 'Lunch',
    );
    expect(filtered.map((item) => item.id), ['listing-Dal']);
    expect(paused.isPaused, isTrue);
    expect(paused.canAddToCart, isFalse);

    final nonVeg = applyHomeListingFilters(
      [expired, vegActive],
      foodType: foodTypeNonVeg,
    );
    expect(nonVeg.single.name, 'Chicken Biryani');
    expect(nonVeg.single.isExpired, isTrue);
  });

  test('available listings appear before unavailable listings', () {
    final expired = FoodItem.fromJson(
      _listingJson(name: 'Chicken Biryani', status: 'expired'),
    );
    final soldOut = FoodItem.fromJson(
      _listingJson(name: 'Sold Dosa', quantity: 0),
    );
    final active = FoodItem.fromJson(_listingJson(name: 'Dal'));

    final ordered = applyHomeListingFilters([expired, soldOut, active]);
    expect(ordered.map((item) => item.name), [
      'Dal',
      'Chicken Biryani',
      'Sold Dosa',
    ]);
  });

  testWidgets('expired listing shows unavailable label and no Add button', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            _listingJson(name: 'Chicken Biryani', status: 'expired'),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Chicken Biryani'), findsWidgets);
    expect(find.text('Not available now'), findsWidgets);
    expect(find.text('All Items'), findsOneWidget);
    expect(find.text('Available Now'), findsNothing);
    expect(find.text('Add'), findsNothing);
    expect(find.byType(MarketplacePurchaseSlot), findsWidgets);
  });

  testWidgets('food detail disables order for expired listings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: FoodDetailScreen(
          food: FoodItem.fromJson(
            _listingJson(name: 'Chicken Biryani', status: 'expired'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Temporarily not available'), findsWidgets);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.text('Order Now'), findsNothing);
  });

  testWidgets('Pause All confirms and surfaces an empty eligibility message', (
    tester,
  ) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_name': 'Anita',
      'phone': '9999999999',
      'society_name': 'Green Heights',
    });
    MyListingsCache.clear();
    addTearDown(MyListingsCache.clear);

    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [_listingJson(name: 'Samosa')],
          pauseAllListings: () async {
            throw Exception('No listings are currently available to pause.');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Pause All'), findsOneWidget);
    expect(find.text('Renew All'), findsOneWidget);

    await tester.tap(find.text('Pause All'));
    await tester.pumpAndSettle();
    expect(find.text('Pause all listings?'), findsOneWidget);
    expect(
      find.text('Your kitchen will temporarily stop accepting new orders.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pause All'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-pause-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('No listings are currently available to pause.'),
      findsOneWidget,
    );
  });

  testWidgets('Renew All confirms and surfaces an empty eligibility message', (
    tester,
  ) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_name': 'Anita',
      'phone': '9999999999',
      'society_name': 'Green Heights',
    });
    MyListingsCache.clear();
    addTearDown(MyListingsCache.clear);

    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [_listingJson(name: 'Samosa')],
          resumeAllListings: () async {
            throw Exception('No paused listings are eligible to renew.');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Renew All'));
    await tester.pumpAndSettle();
    expect(find.text('Renew all listings?'), findsOneWidget);
    expect(
      find.text('Eligible paused listings will become available again.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-renew-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('No paused listings are eligible to renew.'),
      findsOneWidget,
    );
  });
}
