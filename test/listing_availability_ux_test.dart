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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('home All Items previews 12 rows then See all expands', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final listings = List.generate(
      16,
      (i) => _listingJson(name: 'Dish $i'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(fetchListings: () async => listings),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('home-see-all-items')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-see-all-items')));
    await tester.pump();

    expect(find.byKey(const Key('home-see-all-items')), findsNothing);
  });

  testWidgets('Home search shows matching listings as the user types', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            _listingJson(name: 'Birthday Cakes'),
            _listingJson(name: 'Chicken Biryani'),
            _listingJson(name: 'Tomato Pickle'),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('All Items'), findsOneWidget);
    expect(find.text('Tomato Pickle'), findsWidgets);

    await tester.enterText(find.byKey(const Key('home-search-field')), 'pick');
    await tester.pump();

    expect(find.text('Tomato Pickle'), findsWidgets);
    expect(find.text('Chicken Biryani'), findsNothing);
    expect(find.text('Birthday Cakes'), findsNothing);
    expect(find.text('All Items'), findsNothing);
    expect(find.text('1 match'), findsOneWidget);
  });

  testWidgets('Home All Items includes nearby-eligible dishes from other societies', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [_listingJson(name: 'Notting Hill Dal')],
          fetchNearbySellers: () async => {
            'available': true,
            'sellers': [
              {
                'seller': {
                  'id': 'aarav',
                  'name': 'Aarav',
                  'societyName': 'Prestige Ferns Residency',
                  'distanceKm': 8.2,
                },
                'listings': [
                  _listingJson(name: 'veg Sushi')
                    ..['id'] = 'aarav-sushi'
                    ..['sellerId'] = 'aarav'
                    ..['sellerName'] = 'Aarav',
                ],
              },
            ],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Notting Hill Dal'), findsWidgets);
    expect(find.text('veg Sushi'), findsWidgets);
  });

  testWidgets('Home splits society, nearby and extended into labelled sections', (
    tester,
  ) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({'society_id': 'mine'});
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            _listingJson(name: 'Society Dal')..['societyId'] = 'mine',
          ],
          fetchNearbySellers: () async => {
            'available': true,
            'nearbyRadiusKm': 8,
            'extendedRadiusKm': 15,
            'sellers': [
              {
                'seller': {
                  'id': 'near-cook',
                  'name': 'Nearby Cook',
                  'sellingReachLevel': 'NEARBY',
                },
                'listings': [
                  _listingJson(name: 'Nearby Idli')
                    ..['id'] = 'near-idli'
                    ..['societyId'] = 'near-soc'
                    ..['sellerId'] = 'near-cook'
                    ..['sellerName'] = 'Nearby Cook',
                ],
              },
              {
                'seller': {
                  'id': 'ext-cook',
                  'name': 'Extended Cook',
                  'sellingReachLevel': 'EXTENDED',
                },
                'listings': [
                  _listingJson(name: 'Extended Dosa')
                    ..['id'] = 'ext-dosa'
                    ..['societyId'] = 'ext-soc'
                    ..['sellerId'] = 'ext-cook'
                    ..['sellerName'] = 'Extended Cook',
                ],
              },
            ],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Top Sellers in Your Society'), findsOneWidget);
    expect(find.text("Today's Specials in Your Society"), findsOneWidget);
    expect(find.text('Nearby Societies'), findsOneWidget);
    expect(find.text('Sellers within ~8 km'), findsOneWidget);
    expect(find.text('More Around You'), findsOneWidget);
    expect(find.text('From other societies (within ~15 km)'), findsOneWidget);
    expect(find.text('Top Rated Sellers'), findsNothing);
    expect(find.text('In Your Society'), findsNothing);
    expect(find.text("Today's Specials"), findsNothing);
    expect(find.text('Nearby'), findsNothing);
    expect(find.text('Extended Reach'), findsNothing);
    expect(find.text('Society Dal'), findsWidgets);
    expect(find.text('Nearby Idli'), findsWidgets);
    expect(find.text('Extended Dosa'), findsWidgets);
    expect(find.text('All Items'), findsOneWidget);

    double dy(String title) => tester.getTopLeft(find.text(title).first).dy;
    expect(
      dy('Top Sellers in Your Society'),
      lessThan(dy("Today's Specials in Your Society")),
    );
    expect(
      dy("Today's Specials in Your Society"),
      lessThan(dy('Nearby Societies')),
    );
    expect(dy('Nearby Societies'), lessThan(dy('Nearby Idli')));
    expect(dy('Nearby Idli'), lessThan(dy('More Around You')));
    expect(dy('More Around You'), lessThan(dy('Extended Dosa')));
    expect(
      dy('Top Sellers in Your Society'),
      lessThan(dy('Nearby Societies')),
    );
  });

  testWidgets(
    'Home groups next-door EXTENDED sellers as Nearby using distance not opt-in',
    (tester) async {
      _ignoreOverflow();
      SharedPreferences.setMockInitialValues({'society_id': 'mine'});
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            fetchListings: () async => [
              _listingJson(name: 'Society Dal')..['societyId'] = 'mine',
            ],
            fetchNearbySellers: () async => {
              'available': true,
              'nearbyRadiusKm': 8,
              'extendedRadiusKm': 15,
              'sellers': [
                {
                  'seller': {
                    'id': 'puran',
                    'name': 'Puran Agrawal',
                    'sellingReachLevel': 'EXTENDED',
                    'distanceKm': 0.16,
                  },
                  'listings': [
                    _listingJson(name: 'Notting Hill Biryani')
                      ..['id'] = 'pnh-biryani'
                      ..['societyId'] = 'notting'
                      ..['sellerId'] = 'puran'
                      ..['sellerName'] = 'Puran Agrawal',
                  ],
                },
                {
                  'seller': {
                    'id': 'aarav',
                    'name': 'Aarav',
                    'sellingReachLevel': 'EXTENDED',
                    'distanceKm': 8.33,
                  },
                  'listings': [
                    _listingJson(name: 'Ferns Sushi')
                      ..['id'] = 'ferns-sushi'
                      ..['societyId'] = 'ferns'
                      ..['sellerId'] = 'aarav'
                      ..['sellerName'] = 'Aarav',
                  ],
                },
              ],
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Nearby Societies'), findsOneWidget);
      expect(find.text('More Around You'), findsOneWidget);

      final nearbySellers = find.byKey(const Key('home-sellers-nearby'));
      final extendedSellers = find.byKey(const Key('home-sellers-extended'));
      expect(
        find.descendant(of: nearbySellers, matching: find.text('Puran Agrawal')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: nearbySellers, matching: find.text('Aarav')),
        findsNothing,
      );
      expect(
        find.descendant(of: extendedSellers, matching: find.text('Aarav')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: extendedSellers, matching: find.text('Puran Agrawal')),
        findsNothing,
      );
    },
  );

  testWidgets('Home omits Nearby and Extended headings when those buckets are empty', (
    tester,
  ) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({'society_id': 'mine'});
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            _listingJson(name: 'Society Dal')..['societyId'] = 'mine',
          ],
          fetchNearbySellers: () async => {
            'available': true,
            'sellers': <Map<String, dynamic>>[],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("Today's Specials in Your Society"), findsOneWidget);
    expect(find.text('Top Sellers in Your Society'), findsOneWidget);
    expect(find.text('In Your Society'), findsNothing);
    expect(find.text('Nearby Societies'), findsNothing);
    expect(find.text('More Around You'), findsNothing);
    expect(find.text('Nearby'), findsNothing);
    expect(find.text('Extended Reach'), findsNothing);
    expect(find.byKey(const Key('home-see-all-nearby')), findsNothing);
    expect(find.byKey(const Key('home-see-all-extended')), findsNothing);
  });

  testWidgets('Non-Veg filter hides veg specials and does not rename remaining cards', (
    tester,
  ) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({'society_id': 'mine'});
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            _listingJson(name: 'goungura pickle')
              ..['societyId'] = 'mine'
              ..['sellerName'] = 'Sirisha'
              ..['sellerId'] = 'sirisha',
            _listingJson(name: 'Dry fruit dessert')
              ..['id'] = 'dry-fruit'
              ..['societyId'] = 'mine'
              ..['sellerName'] = 'Amita Agarwal'
              ..['sellerId'] = 'amita'
              ..['price'] = 150,
            _listingJson(
              name: 'Hyderabadi Chicken Biryani',
              foodType: 'NON_VEG',
              status: 'expired',
            )
              ..['id'] = 'seed-listing-biryani'
              ..['societyId'] = 'mine'
              ..['sellerName'] = 'Amita Agarwal'
              ..['sellerId'] = 'amita'
              ..['price'] = 220,
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('goungura pickle'), findsWidgets);
    expect(find.text('Dry fruit dessert'), findsWidgets);
    expect(find.text('Hyderabadi Chicken Biryani'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('home-food-type-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('home-food-type-toggle')));
    await tester.pump();

    expect(find.text('Non-Veg'), findsOneWidget);
    expect(find.text('goungura pickle'), findsNothing);
    expect(find.text('Dry fruit dessert'), findsNothing);
    expect(find.text('Hyderabadi Chicken Biryani'), findsWidgets);
    expect(find.textContaining('Sirisha'), findsNothing);
    expect(find.textContaining('Amita Agarwal'), findsWidgets);
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
    expect(find.text('Out of stock'), findsWidgets);
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

    expect(find.text('Out of stock'), findsWidgets);
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

  testWidgets('compact listing card keeps Add horizontal when sold count shows', (
    tester,
  ) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({'society_id': 'mine'});
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            _listingJson(name: 'veg Sushi', quantity: 38)
              ..['societyId'] = 'mine'
              ..['price'] = 90
              ..['quantitySold'] = 2,
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('2 sold'), findsWidgets);
    expect(find.text('REGULAR'), findsWidgets);
    final price = tester.getRect(find.text('₹90').first);
    final sold = tester.getRect(find.text('2 sold').first);
    expect(sold.top, greaterThan(price.bottom - 1));

    final addSize = tester.getSize(find.text('Add').first);
    expect(addSize.width, greaterThan(addSize.height));
  });
}
