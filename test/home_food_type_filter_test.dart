import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/food_type.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/widgets/food_type_selector.dart';

FoodItem _item({
  required String id,
  required String name,
  String? foodType,
  String? category,
  String sellerName = 'Anita',
  List<String> tags = const [],
  String? campaignId,
}) {
  return FoodItem.fromJson({
    'id': id,
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': sellerName,
    'price': 100,
    'foodType': foodType,
    'category': category,
    'tags': tags,
    'campaignId': campaignId,
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
}
