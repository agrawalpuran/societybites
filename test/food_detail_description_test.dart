import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/food_detail_screen.dart';

FoodItem _food({required String name, required String description}) {
  return FoodItem.fromJson({
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 250,
    'status': 'active',
    'description': description,
    'quantity': 15,
    'foodType': 'VEG',
    'category': 'Snacks',
    'tags': ['Homemade', 'Fresh'],
  });
}

void main() {
  testWidgets('food detail shows the listing description, not a shared story', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodDetailScreen(
          food: _food(
            name: 'Gongura pickle',
            description: 'Tangy gongura pickle made with fresh leaves and spices.',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Tangy gongura pickle made with fresh leaves and spices.'),
      findsOneWidget,
    );
    expect(find.textContaining('black lentils'), findsNothing);
    expect(find.textContaining('dhungar'), findsNothing);
  });

  testWidgets('food detail has a fallback when description is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FoodDetailScreen(
          food: _food(name: 'Samosa', description: ''),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('The seller has not added a description yet.'),
      findsOneWidget,
    );
  });
}
