import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/orders_screen.dart';

Map<String, dynamic> _orderJson({
  required String id,
  required String orderNumber,
  required String itemName,
}) {
  return {
    'id': id,
    'orderNumber': orderNumber,
    'status': 'accepted',
    'items': [
      {
        'quantity': 1,
        'unitPrice': 120,
        'listing': {
          'id': 'listing-$id',
          'name': itemName,
          'sellerId': 'seller-1',
          'price': 120,
        },
      },
    ],
  };
}

final _buyerOrder = _orderJson(
  id: 'buyer-order-1',
  orderNumber: 'BUY-1',
  itemName: 'Buyer Biryani',
);

final _sellerOrder = _orderJson(
  id: 'seller-order-1',
  orderNumber: 'SELL-1',
  itemName: 'Seller Pasta',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
  });

  Future<void> pumpOrders(
    WidgetTester tester, {
    required Future<List<Map<String, dynamic>>> Function({required String role})
    fetchOrders,
    GlobalKey<OrdersScreenState>? key,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(key: key, fetchOrders: fetchOrders),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('first Buying load calls the buyer API', (tester) async {
    final roles = <String>[];
    await pumpOrders(
      tester,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        return role == 'buyer' ? [_buyerOrder] : [_sellerOrder];
      },
    );

    expect(roles, ['buyer']);
    expect(find.text('Buyer Biryani'), findsOneWidget);
    expect(find.text('Seller Pasta'), findsNothing);
  });

  testWidgets('first Selling switch calls the seller API', (tester) async {
    final roles = <String>[];
    await pumpOrders(
      tester,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        return role == 'buyer' ? [_buyerOrder] : [_sellerOrder];
      },
    );

    await tester.tap(find.text('Selling'));
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'seller']);
    expect(find.text('Seller Pasta'), findsOneWidget);
    expect(find.text('Buyer Biryani'), findsNothing);
  });

  testWidgets(
    'switching roles after both loaded reuses cache without refetch or spinner',
    (tester) async {
      final roles = <String>[];
      await pumpOrders(
        tester,
        fetchOrders: ({required String role}) async {
          roles.add(role);
          return role == 'buyer' ? [_buyerOrder] : [_sellerOrder];
        },
      );

      await tester.tap(find.text('Selling'));
      await tester.pump();
      await tester.pump();
      expect(roles, ['buyer', 'seller']);
      expect(find.text('Seller Pasta'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Buying'));
      await tester.pump();
      expect(roles, ['buyer', 'seller']);
      expect(find.text('Buyer Biryani'), findsOneWidget);
      expect(find.text('Seller Pasta'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Selling'));
      await tester.pump();
      expect(roles, ['buyer', 'seller']);
      expect(find.text('Seller Pasta'), findsOneWidget);
      expect(find.text('Buyer Biryani'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('pull-to-refresh fetches the currently selected role', (
    tester,
  ) async {
    final roles = <String>[];
    await pumpOrders(
      tester,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        return role == 'buyer' ? [_buyerOrder] : [_sellerOrder];
      },
    );

    await tester.tap(find.text('Selling'));
    await tester.pump();
    await tester.pump();
    expect(roles, ['buyer', 'seller']);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'seller', 'seller']);
  });

  testWidgets('failed initial load can still be retried by switching back', (
    tester,
  ) async {
    var buyerAttempts = 0;
    final roles = <String>[];
    await pumpOrders(
      tester,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        if (role == 'buyer') {
          buyerAttempts++;
          if (buyerAttempts == 1) {
            throw Exception('network down');
          }
          return [_buyerOrder];
        }
        return [_sellerOrder];
      },
    );

    expect(roles, ['buyer']);
    expect(find.textContaining('network down'), findsOneWidget);

    await tester.tap(find.text('Selling'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Seller Pasta'), findsOneWidget);

    await tester.tap(find.text('Buying'));
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'seller', 'buyer']);
    expect(find.text('Buyer Biryani'), findsOneWidget);
  });

  testWidgets('FCM-style explicit refresh still fetches the current role', (
    tester,
  ) async {
    final roles = <String>[];
    final key = GlobalKey<OrdersScreenState>();
    await pumpOrders(
      tester,
      key: key,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        return role == 'buyer' ? [_buyerOrder] : [_sellerOrder];
      },
    );

    await tester.tap(find.text('Selling'));
    await tester.pump();
    await tester.pump();
    expect(roles, ['buyer', 'seller']);

    key.currentState!.refresh();
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'seller', 'seller']);
    expect(find.text('Seller Pasta'), findsOneWidget);

    await tester.tap(find.text('Buying'));
    await tester.pump();
    key.currentState!.refresh();
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'seller', 'seller', 'buyer']);
    expect(find.text('Buyer Biryani'), findsOneWidget);
  });
}
