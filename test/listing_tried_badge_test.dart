import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/widgets/listing_image.dart';
import 'package:societybites/widgets/listing_tried_badge.dart';
import 'package:societybites/web/web_food_card.dart';

FoodItem _food({bool purchasedBefore = false}) {
  return FoodItem(
    id: 'l1',
    name: 'Paneer puff',
    sellerId: 's1',
    sellerName: 'Krunch Cart',
    block: 'Block C',
    price: 80,
    rating: 4.5,
    reviewCount: 3,
    pickupTime: '15 min',
    description: '',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
    purchasedBefore: purchasedBefore,
  );
}

void main() {
  test('FoodItem.fromJson defaults purchasedBefore to false', () {
    final parsed = FoodItem.fromJson({
      'id': 'listing-1',
      'name': 'Paneer puff',
      'sellerId': 's1',
      'sellerName': 'Krunch Cart',
      'block': 'C',
      'price': 80,
      'avgRating': 0,
    });
    expect(parsed.purchasedBefore, isFalse);
  });

  test('FoodItem.fromJson reads purchasedBefore', () {
    final parsed = FoodItem.fromJson({
      'id': 'listing-1',
      'name': 'Paneer puff',
      'sellerId': 's1',
      'sellerName': 'Krunch Cart',
      'block': 'C',
      'price': 80,
      'avgRating': 0,
      'purchasedBefore': true,
    });
    expect(parsed.purchasedBefore, isTrue);
  });

  testWidgets('TRIED badge is absent when purchasedBefore is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListingTriedBadge(food: _food())),
      ),
    );
    expect(find.byKey(const Key('listing-tried-badge')), findsNothing);
    expect(find.text('Tried'), findsNothing);
  });

  testWidgets('TRIED badge shows repeat icon and label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingTriedBadge(food: _food(purchasedBefore: true)),
        ),
      ),
    );
    expect(find.byKey(const Key('listing-tried-badge')), findsOneWidget);
    expect(find.text('Tried'), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
  });

  testWidgets('ListingImage overlays TRIED only when enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingImage(
            food: _food(purchasedBefore: true),
            width: 112,
            height: 112,
            showTriedBadge: true,
          ),
        ),
      ),
    );
    expect(find.text('Tried'), findsOneWidget);
  });

  testWidgets('ListingImage does not show TRIED on seller/order thumbs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingImage(
            food: _food(purchasedBefore: true),
            width: 72,
            height: 72,
          ),
        ),
      ),
    );
    expect(find.text('Tried'), findsNothing);
  });

  testWidgets('web listing card shows TRIED without changing ADD', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: WebFoodCard(
              food: _food(purchasedBefore: true),
              cartQty: 0,
              onAdd: () {},
              onRemove: () {},
              onOpen: () {},
              onSeller: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Tried'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
