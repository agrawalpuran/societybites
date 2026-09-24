import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/services/cart_controller.dart';
import 'package:societybites/widgets/floating_cart_bar.dart';

void main() {
  tearDown(CartController.instance.clear);

  testWidgets('floating cart is hidden when empty and opens checkout path when filled',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(floatingActionButton: FloatingCartBar()),
      ),
    );
    expect(find.byKey(const Key('home-floating-cart')), findsNothing);

    CartController.instance.items.add(
      CartItem(
        food: FoodItem(
          id: 'pastries',
          name: 'Pastries',
          sellerId: 's1',
          sellerName: 'Puran',
          block: 'A',
          price: 75,
          rating: 5,
          pickupTime: '5 PM',
          description: '',
          icon: Icons.cake,
          bgColor: const Color(0xFFE8F5EE),
        ),
        quantity: 2,
      ),
    );
    CartController.instance.notify();
    await tester.pump();

    expect(find.byKey(const Key('home-floating-cart')), findsOneWidget);
    expect(find.textContaining('2 items'), findsOneWidget);
    expect(find.textContaining('₹150'), findsOneWidget);
  });
}
