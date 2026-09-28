import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/checkout_screen.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/services/cart_controller.dart';

FoodItem _food() {
  return FoodItem(
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
  );
}

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void main() {
  tearDown(CartController.instance.clear);

  testWidgets('emptying cart returns to existing Home without a spinner', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Column(
                children: [
                  const Text('Home listings stay'),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CheckoutScreen(
                            cartItems: [CartItem(food: _food(), quantity: 1)],
                          ),
                        ),
                      );
                    },
                    child: const Text('Open cart'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open cart'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Kachori Chat'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    await tester.pump();

    expect(find.text('Home listings stay'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Fresh Kachori Chat'), findsNothing);
    expect(CartController.instance.items, isEmpty);
  });

  testWidgets('My Kitchen first load shows the page shell and skeletons', (
    tester,
  ) async {
    final orders = Completer<List<Map<String, dynamic>>>();
    final campaigns = Completer<List<Map<String, dynamic>>>();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: SellerDashboardScreen(
          fetchOrders: () => orders.future,
          fetchCampaigns: () => campaigns.future,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Orders'), findsWidgets);
    expect(find.byKey(const Key('kitchen-orders-skeletons')), findsOneWidget);
    expect(find.text('Loading orders…'), findsNothing);

    orders.complete(const []);
    campaigns.complete(const []);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('kitchen-orders-skeletons')), findsNothing);
    expect(find.textContaining('No active orders yet'), findsOneWidget);
  });
}
