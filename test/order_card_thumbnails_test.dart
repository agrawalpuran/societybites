import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/orders_screen.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/widgets/listing_image.dart';

Map<String, dynamic> _line(String name) {
  return {
    'quantity': 1,
    'unitPrice': 25,
    'listing': {
      'id': name,
      'name': name,
      'sellerId': 'seller-1',
      'sellerName': 'Puran Agrawal',
      'price': 25,
      'imageUrl': 'https://example.com/$name.jpg',
    },
  };
}

Map<String, dynamic> _order(List<Map<String, dynamic>> items) {
  return {
    'id': 'o-multi',
    'orderNumber': 'SB-multi',
    'status': 'completed',
    'paymentStatus': 'paid',
    'paymentMethod': 'upi',
    'total': 50,
    'subtotal': 50,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'completedAt': DateTime.now().toUtc().toIso8601String(),
    'items': items,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('multi-item buyer order card shows one thumbnail per dish', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'user_name': 'Test1'});
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [
            _order([_line('Besan Kachori'), _line("Dadi's Dhokla")]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 items (2 portions)'), findsOneWidget);
    expect(find.text('Besan Kachori'), findsOneWidget);
    expect(find.text("Dadi's Dhokla"), findsOneWidget);
    expect(find.byType(ListingImage), findsNWidgets(2));
  });

  testWidgets('single-item buyer order card keeps its thumbnail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'user_name': 'Test1'});
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [
            _order([_line("Dadi's Dhokla")]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Dadi's Dhokla"), findsOneWidget);
    expect(find.byType(ListingImage), findsOneWidget);
  });

  testWidgets('multi-item seller order card shows one thumbnail per dish', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerActiveOrderCard(
            order: Order.fromJson(
              _order([_line('Besan Kachori'), _line("Dadi's Dhokla")]),
            ),
            onAction: (_, _) async {},
            onOrderUpdated: (_) {},
            onPaymentConfirmed: () async {},
            onReject: (_) async {},
            onReadyBy: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Besan Kachori'), findsOneWidget);
    expect(find.byType(ListingImage), findsNWidgets(2));
  });
}
