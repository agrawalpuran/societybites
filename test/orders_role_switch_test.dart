import 'dart:async';

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

  testWidgets('Orders loads buyer orders without Buying or Selling toggles', (
    tester,
  ) async {
    final roles = <String>[];
    await pumpOrders(
      tester,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        return [_buyerOrder];
      },
    );

    expect(roles, ['buyer']);
    expect(find.text('Buyer Biryani'), findsOneWidget);
    expect(find.text('Buying'), findsNothing);
    expect(find.text('Selling'), findsNothing);
  });

  testWidgets('pull-to-refresh fetches buyer orders', (
    tester,
  ) async {
    final roles = <String>[];
    await pumpOrders(
      tester,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        return [_buyerOrder];
      },
    );

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'buyer']);
  });

  testWidgets('failed initial load can be retried explicitly', (
    tester,
  ) async {
    var buyerAttempts = 0;
    final roles = <String>[];
    final key = GlobalKey<OrdersScreenState>();
    await pumpOrders(
      tester,
      key: key,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        buyerAttempts++;
        if (buyerAttempts == 1) {
          throw Exception('network down');
        }
        return [_buyerOrder];
      },
    );

    expect(roles, ['buyer']);
    expect(find.textContaining('network down'), findsOneWidget);

    key.currentState!.refresh();
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'buyer']);
    expect(find.text('Buyer Biryani'), findsOneWidget);
  });

  testWidgets('FCM-style explicit refresh fetches buyer orders', (
    tester,
  ) async {
    final roles = <String>[];
    final key = GlobalKey<OrdersScreenState>();
    await pumpOrders(
      tester,
      key: key,
      fetchOrders: ({required String role}) async {
        roles.add(role);
        return [_buyerOrder];
      },
    );

    key.currentState!.refresh();
    await tester.pump();
    await tester.pump();

    expect(roles, ['buyer', 'buyer']);
    expect(find.text('Buyer Biryani'), findsOneWidget);
  });

  testWidgets('first Buying load shows loading copy then orders', (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    await pumpOrders(
      tester,
      fetchOrders: ({required String role}) => pending.future,
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Loading orders…'), findsNothing);
    expect(find.byKey(const Key('kitchen-orders-skeletons')), findsOneWidget);

    pending.complete([_buyerOrder]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Buyer Biryani'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Buying refresh keeps existing orders visible', (tester) async {
    var calls = 0;
    final hang = Completer<List<Map<String, dynamic>>>();
    final key = GlobalKey<OrdersScreenState>();
    await pumpOrders(
      tester,
      key: key,
      fetchOrders: ({required String role}) {
        calls++;
        if (calls == 1) {
          return Future.value([_buyerOrder]);
        }
        return hang.future;
      },
    );

    expect(find.text('Buyer Biryani'), findsOneWidget);

    key.currentState!.refresh();
    await tester.pump();

    expect(find.text('Buyer Biryani'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    hang.complete([_buyerOrder]);
    await tester.pump();
  });

  testWidgets('failed Buying refresh keeps existing orders', (tester) async {
    var calls = 0;
    final key = GlobalKey<OrdersScreenState>();
    await pumpOrders(
      tester,
      key: key,
      fetchOrders: ({required String role}) async {
        calls++;
        if (calls == 1) return [_buyerOrder];
        throw Exception('refresh failed');
      },
    );

    expect(find.text('Buyer Biryani'), findsOneWidget);

    key.currentState!.refresh();
    await tester.pump();
    await tester.pump();

    expect(find.text('Buyer Biryani'), findsOneWidget);
    expect(find.textContaining('refresh failed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

}
