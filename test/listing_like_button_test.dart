import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/widgets/listing_like_button.dart';

FoodItem _food({int likeCount = 0, bool likedByMe = false}) {
  return FoodItem(
    id: 'l1',
    name: 'Test',
    sellerId: 's1',
    sellerName: 'Seller',
    block: 'Block C',
    flatNumber: '3062',
    price: 100,
    rating: 0,
    pickupTime: '15 min',
    description: '',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
    likeCount: likeCount,
    likedByMe: likedByMe,
  );
}

void main() {
  testWidgets('outline heart hides a zero count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ListingLikeButton(food: _food()))),
    );
    final heart = tester.widget<Icon>(find.byIcon(Icons.favorite_border_rounded));
    expect(heart.size, 22);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('filled heart shows the count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListingLikeButton(food: _food(likeCount: 12, likedByMe: true)),
        ),
      ),
    );
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
