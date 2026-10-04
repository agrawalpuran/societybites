import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/food_type.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/models/selling_reach.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/widgets/home_distance_chip.dart';

FoodItem _food(
  String name, {
  String availabilityMode = listingAvailabilityReadyNow,
  String? foodType = foodTypeVeg,
  String catalogType = listingCatalogRegular,
}) {
  return FoodItem.fromJson({
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 80,
    'status': 'active',
    'quantity': 4,
    'catalogType': catalogType,
    'availabilityMode': availabilityMode,
    'foodType': foodType,
    'category': 'Snacks',
  });
}

void main() {
  final ready = _food('Samosa');
  final made = _food(
    'Cake',
    availabilityMode: listingAvailabilityMadeToOrder,
    foodType: foodTypeVeg,
  );
  final chicken = _food('Chicken', foodType: foodTypeNonVeg);
  final preorder = _food('Diwali Box', catalogType: listingCatalogPreorder);

  test('type All keeps regular and made-to-order listings', () {
    final result = applyHomeListingFilters([ready, made, chicken, preorder]);
    expect(result.map((item) => item.name), ['Samosa', 'Cake', 'Chicken']);
  });

  test('Regular excludes made to order and pre-order catalog', () {
    final result = applyHomeListingFilters(
      [ready, made, preorder],
      listingType: HomeListingType.regular,
    );
    expect(result.map((item) => item.name), ['Samosa']);
  });

  test('Made to Order keeps only isMadeToOrder listings', () {
    final result = applyHomeListingFilters(
      [ready, made, chicken],
      foodType: foodTypeVeg,
      listingType: HomeListingType.madeToOrder,
    );
    expect(result.map((item) => item.name), ['Cake']);
  });

  test('Pre-order listing type does not use the regular feed', () {
    final result = applyHomeListingFilters(
      [ready, made],
      listingType: HomeListingType.preOrder,
    );
    expect(result, isEmpty);
  });

  test('pre-order campaigns follow veg and search', () {
    final veg = PreOrderCampaign(
      id: 'c1',
      title: 'Friday Thali',
      status: 'open',
      orderOpenAt: DateTime(2026, 1, 1),
      orderCutoffAt: DateTime(2026, 12, 1),
      fulfilmentAt: DateTime(2026, 12, 2),
      products: const [
        PreOrderProduct(
          listingId: 'p1',
          name: 'Veg Thali',
          sellerId: 's',
          sellerName: 'Anita',
          price: 100,
          inventoryMode: 'demand',
          quantity: 1,
          foodType: foodTypeVeg,
        ),
      ],
    );
    final nonVeg = PreOrderCampaign(
      id: 'c2',
      title: 'Grill Night',
      status: 'open',
      orderOpenAt: DateTime(2026, 1, 1),
      orderCutoffAt: DateTime(2026, 12, 1),
      fulfilmentAt: DateTime(2026, 12, 2),
      products: const [
        PreOrderProduct(
          listingId: 'p2',
          name: 'Chicken',
          sellerId: 's',
          sellerName: 'Anita',
          price: 120,
          inventoryMode: 'demand',
          quantity: 1,
          foodType: foodTypeNonVeg,
        ),
      ],
    );

    expect(
      campaignsMatchingHomeTypeFilters(
        [veg, nonVeg],
        foodType: foodTypeVeg,
      ).map((campaign) => campaign.title),
      ['Friday Thali'],
    );
    expect(
      campaignsMatchingHomeTypeFilters(
        [veg, nonVeg],
        searchQuery: 'grill',
      ).map((campaign) => campaign.title),
      ['Grill Night'],
    );
    expect(
      campaignsMatchingHomeTypeFilters([veg], category: 'Breakfast'),
      isEmpty,
    );
  });

  testWidgets('Type opens a single compact choice list', (tester) async {
    HomeListingType? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDistanceChip(
            reach: const SellingReach(nearbyRadiusKm: 5, extendedRadiusKm: 10),
            selected: null,
            itemCount: 3,
            onSelected: (_) {},
            onListingTypeSelected: (type) => picked = type,
          ),
        ),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Up to 10 km'), findsOneWidget);
    expect(find.text('Regular'), findsNothing);
    await tester.tap(find.byKey(const Key('home-listing-type-chip')));
    await tester.pumpAndSettle();
    expect(find.text('Made to Order'), findsOneWidget);
    expect(find.text('Pre-order'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-listing-type-madeToOrder')));
    await tester.pumpAndSettle();
    expect(picked, HomeListingType.madeToOrder);
  });
}
