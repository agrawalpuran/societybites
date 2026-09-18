import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/food_type.dart';
import 'package:societybites/models/listing_categories.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/widgets/available_in_selector.dart';

FoodItem _item({
  required String id,
  required String name,
  String? foodType,
  String? category,
  List<String>? categories,
  String catalogType = 'REGULAR',
}) {
  return FoodItem.fromJson({
    'id': id,
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 100,
    'foodType': foodType,
    'category': category,
    if (categories != null) 'categories': categories,
    'catalogType': catalogType,
  });
}

void main() {
  test('single category listing saves as a one-element collection', () {
    final item = _item(id: '1', name: 'Poha', category: 'Breakfast');
    expect(item.listingCategories, ['Breakfast']);
    expect(formatAvailableIn(item.listingCategories), 'Breakfast');
  });

  test('multiple categories parse from API payload', () {
    final item = _item(
      id: '2',
      name: 'Thali',
      categories: ['BREAKFAST', 'Lunch'],
    );
    expect(item.listingCategories, ['Breakfast', 'Lunch']);
    expect(formatAvailableIn(item.listingCategories), 'Breakfast, Lunch');
  });

  test('All Categories selects every food category', () {
    final selected = toggleListingCategory(
      {},
      option: allListingCategoriesLabel,
      selected: true,
    );
    expect(selected, listingFoodCategories.toSet());
    expect(isAllListingCategoriesSelected(selected), isTrue);
    expect(formatAvailableIn(selected), allListingCategoriesLabel);
  });

  test('deselecting one category unchecks All Categories', () {
    var selected = listingFoodCategories.toSet();
    selected = toggleListingCategory(
      selected,
      option: 'Lunch',
      selected: false,
    );
    expect(isAllListingCategoriesSelected(selected), isFalse);
    expect(selected.contains('Lunch'), isFalse);
    expect(selected.contains('Breakfast'), isTrue);
  });

  test('selecting all five individually checks All Categories', () {
    var selected = <String>{};
    for (final category in listingFoodCategories) {
      selected = toggleListingCategory(
        selected,
        option: category,
        selected: true,
      );
    }
    expect(isAllListingCategoriesSelected(selected), isTrue);
  });

  test('Home filter matches any selected category', () {
    final listings = [
      _item(
        id: 'mix',
        name: 'Dhokla',
        foodType: foodTypeVeg,
        categories: ['Breakfast', 'Lunch'],
      ),
    ];
    expect(
      applyHomeListingFilters(listings, category: 'Breakfast').map((e) => e.id),
      ['mix'],
    );
    expect(
      applyHomeListingFilters(listings, category: 'Lunch').map((e) => e.id),
      ['mix'],
    );
    expect(
      applyHomeListingFilters(listings, category: 'Dinner'),
      isEmpty,
    );
  });

  test('all-category listing appears under every Home chip', () {
    final listings = [
      _item(
        id: 'all',
        name: 'Festival thali',
        categories: List<String>.from(listingFoodCategories),
      ),
    ];
    for (final category in listingFoodCategories) {
      expect(
        applyHomeListingFilters(listings, category: category).single.id,
        'all',
      );
    }
  });

  test('Veg and category filters stay independent', () {
    final listings = [
      _item(
        id: 'veg',
        name: 'Upma',
        foodType: foodTypeVeg,
        categories: ['Breakfast', 'Lunch'],
      ),
      _item(
        id: 'nv',
        name: 'Keema',
        foodType: foodTypeNonVeg,
        categories: ['Breakfast'],
      ),
    ];
    expect(
      applyHomeListingFilters(
        listings,
        foodType: foodTypeVeg,
        category: 'Breakfast',
      ).map((e) => e.id),
      ['veg'],
    );
    expect(
      applyHomeListingFilters(
        listings,
        foodType: foodTypeVeg,
        category: 'Lunch',
      ).map((e) => e.id),
      ['veg'],
    );
    expect(
      applyHomeListingFilters(
        listings,
        foodType: foodTypeNonVeg,
        category: 'Breakfast',
      ).map((e) => e.id),
      ['nv'],
    );
  });

  test('legacy single category still filters on Home', () {
    final listings = [_item(id: 'old', name: 'Idli', category: 'Breakfast')];
    expect(
      applyHomeListingFilters(listings, category: 'Breakfast').single.id,
      'old',
    );
  });

  test('PREORDER catalog items stay out of regular marketplace filters', () {
    final listings = [
      _item(
        id: 'pre',
        name: 'Party thali',
        categories: ['Lunch'],
        catalogType: 'PREORDER',
      ),
    ];
    expect(
      applyHomeListingFilters(listings, category: 'Lunch'),
      isEmpty,
    );
  });

  testWidgets('Available In chips follow All Categories rules', (tester) async {
    var selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AvailableInSelector(
                selected: selected,
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text(allListingCategoriesLabel));
    await tester.pump();
    expect(selected, listingFoodCategories.toSet());
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Lunch')).selected,
      isTrue,
    );

    await tester.tap(find.text('Lunch'));
    await tester.pump();
    expect(selected.contains('Lunch'), isFalse);
    expect(
      tester
          .widget<FilterChip>(
            find.widgetWithText(FilterChip, allListingCategoriesLabel),
          )
          .selected,
      isFalse,
    );
  });

  test('Edit Listing selection is derived from the existing category', () {
    final listing = _item(
      id: 'edit-1',
      name: 'Poha',
      category: 'Breakfast',
      foodType: foodTypeVeg,
    );
    final selected = listing.listingCategories
        .where(listingFoodCategories.contains)
        .toSet();
    expect(selected, {'Breakfast'});
    expect(isAllListingCategoriesSelected(selected), isFalse);
  });

  testWidgets('AvailableInSelector reports empty selection', (tester) async {
    var selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvailableInSelector(
            selected: selected,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(selected, isEmpty);
  });
}
