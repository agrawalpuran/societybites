import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/services/cart_controller.dart';
import 'package:flutter/material.dart';

void main() {
  tearDown(() {
    CartController.instance
      ..onOrderPlaced = null
      ..onShowOrdersAfterPlace = null
      ..clear();
  });

  test('handlePlacedOrder clears cart and asks the shell to show Orders', () {
    var homeReloaded = false;
    var showOrders = false;
    CartController.instance.onOrderPlaced = () => homeReloaded = true;
    CartController.instance.onShowOrdersAfterPlace = () => showOrders = true;
    CartController.instance.items.add(
      CartItem(
        food: FoodItem(
          id: '1',
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
      ),
    );

    CartController.instance.handlePlacedOrder();

    expect(CartController.instance.items, isEmpty);
    expect(homeReloaded, isTrue);
    expect(showOrders, isTrue);
  });

  testWidgets(
    'finishPlacedOrder pops listing checkout back to the first route',
    (tester) async {
      var showOrders = false;
      CartController.instance.onShowOrdersAfterPlace = () => showOrders = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: Builder(
                          builder: (inner) => TextButton(
                            onPressed: () {
                              CartController.instance.finishPlacedOrder(inner);
                            },
                            child: const Text('Confirm listing order'),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open listing'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open listing'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm listing order'), findsOneWidget);

      await tester.tap(find.text('Confirm listing order'));
      await tester.pumpAndSettle();

      expect(find.text('Open listing'), findsOneWidget);
      expect(find.text('Confirm listing order'), findsNothing);
      expect(showOrders, isTrue);
    },
  );
}
