import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/checkout_screen.dart';
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

  testWidgets('checkout review header shows Cart with the order quantity',
      (tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = '${details.exception}\n${details.summary}';
      if (text.contains('A RenderFlex overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            CartItem(
              food: FoodItem(
                id: 'kachori',
                name: 'Fresh Kachori Chat',
                sellerId: 's1',
                sellerName: 'Puran',
                block: 'C',
                price: 75,
                rating: 5,
                pickupTime: '5 PM',
                description: '',
                icon: Icons.fastfood,
                bgColor: const Color(0xFFE8F5EE),
                quantity: 15,
              ),
              quantity: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('home-cart-button')), findsOneWidget);
    expect(find.text('Cart'), findsWidgets);
    expect(find.text('1'), findsWidgets);
  });
}
