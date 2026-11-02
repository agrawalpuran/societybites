import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/food_type.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/web/web_food_card.dart';

/// A card with every optional line filled. A fixed-height card overflows
/// when those lines no longer fit, and this test fails on that overflow.
FoodItem _fullCard() {
  return FoodItem(
    id: 'l1',
    name: 'Andhra special gunpowder podi with extra spices',
    sellerId: 's1',
    sellerName: 'Sirisha Lakshmi Narayana',
    block: 'Block E',
    flatNumber: '5122',
    price: 100,
    discountEnabled: true,
    discountPercent: 10,
    discountActive: true,
    effectivePrice: 90,
    rating: 5,
    reviewCount: 5,
    quantitySold: 12,
    likeCount: 24,
    likedByMe: true,
    pickupTime: '15 min',
    description: '',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
    foodType: foodTypeVeg,
    weightValue: '100',
    weightUnit: 'g',
    variantGroupId: 'podi',
    variantOptionCount: 2,
    availabilityMode: listingAvailabilityMadeToOrder,
    preparationTimeMinutes: 45,
    createdAt: DateTime.now(),
  );
}

Future<void> _pumpCard(WidgetTester tester, double width) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: WebFoodCard(
              food: _fullCard(),
              cartQty: 0,
              onAdd: () {},
              onRemove: () {},
              onOpen: () {},
              onSeller: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('full web listing card fits at a narrow width', (tester) async {
    await _pumpCard(tester, 220);
    expect(find.byType(WebFoodCard), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full web listing card fits at a wide width', (tester) async {
    await _pumpCard(tester, 360);
    expect(find.byType(WebFoodCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
