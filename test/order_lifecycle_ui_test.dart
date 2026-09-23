import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/screens/orders_screen.dart';

Map<String, dynamic> _orderJson({
  required String id,
  required String status,
  String itemName = 'Test Dosa',
  String paymentStatus = 'pending',
  String paymentMethod = 'upi',
  int? statusStep,
}) {
  return {
    'id': id,
    'orderNumber': 'SB-$id',
    'status': status,
    'statusStep': statusStep ?? BuyerOrderLifecycle.progressStep(status),
    'paymentStatus': paymentStatus,
    'paymentMethod': paymentMethod,
    'total': 120,
    'subtotal': 115,
    'communityFee': 5,
    'createdAt': '2026-09-12T10:00:00.000Z',
    'items': [
      {
        'quantity': 1,
        'unitPrice': 115,
        'listing': {
          'id': 'listing-$id',
          'name': itemName,
          'sellerId': 'seller-1',
          'sellerName': 'Test Seller',
          'price': 115,
        },
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
  });

  Future<void> pumpOrders(
    WidgetTester tester,
    List<Map<String, dynamic>> orders,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => orders,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('buyer sees confirmed copy after acceptance', (tester) async {
    await pumpOrders(tester, [_orderJson(id: 'a1', status: 'accepted')]);
    expect(find.text('Order confirmed'), findsOneWidget);
    expect(find.text('Your order is being prepared.'), findsOneWidget);
    expect(find.text('Confirmed'), findsWidgets);
    expect(find.text('Start Preparing'), findsNothing);
    expect(find.text('Mark Picked Up'), findsNothing);
    expect(find.text('Mark Complete'), findsNothing);
  });

  testWidgets('buyer sees Ready for Pickup after READY', (tester) async {
    await pumpOrders(tester, [_orderJson(id: 'r1', status: 'ready')]);
    expect(find.text('Ready for Pickup'), findsWidgets);
    expect(
      find.text('Please collect your order from the seller.'),
      findsOneWidget,
    );
    expect(find.text('Mark Picked Up'), findsNothing);
    expect(find.text('Mark Complete'), findsNothing);
    expect(find.text('I\'ve Picked Up'), findsNothing);
  });

  testWidgets('buyer sees Completed after completion', (tester) async {
    await pumpOrders(tester, [_orderJson(id: 'c1', status: 'completed')]);
    await tester.tap(find.textContaining('Past'));
    await tester.pumpAndSettle();
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('Mark Complete'), findsNothing);
  });

  testWidgets('buyer sees Rejected after rejection', (tester) async {
    await pumpOrders(tester, [_orderJson(id: 'x1', status: 'rejected')]);
    await tester.tap(find.textContaining('Past'));
    await tester.pumpAndSettle();
    expect(find.text('ORDER REJECTED'), findsOneWidget);
    expect(
      find.text('Unfortunately, the seller could not fulfil this order.'),
      findsOneWidget,
    );
  });

  testWidgets('buyer has no lifecycle action buttons', (tester) async {
    await pumpOrders(tester, [
      _orderJson(id: 'p1', status: 'pending'),
      _orderJson(id: 'a1', status: 'accepted'),
      _orderJson(id: 'r1', status: 'ready'),
    ]);
    expect(find.text('Accept Order'), findsNothing);
    expect(find.text('Mark Ready'), findsNothing);
    expect(find.text('Complete Order'), findsNothing);
    expect(find.text('Start Preparing'), findsNothing);
    expect(find.text('Mark Picked Up'), findsNothing);
  });

  testWidgets(
    'legacy preparing + seller_confirmed stays Confirmed despite stale statusStep 2',
    (tester) async {
      await pumpOrders(tester, [
        _orderJson(
          id: 'legacy-prep',
          status: 'preparing',
          paymentStatus: 'seller_confirmed',
          statusStep: 2,
        ),
      ]);
      expect(find.text('Order confirmed'), findsOneWidget);
      expect(find.text('Your order is being prepared.'), findsOneWidget);
      expect(find.text('Payment Received ✓'), findsOneWidget);
      expect(
        find.text('Please collect your order from the seller.'),
        findsNothing,
      );
      expect(find.text('Accept Order'), findsNothing);
      expect(find.text('Mark Ready'), findsNothing);
      expect(find.text('Complete Order'), findsNothing);
    },
  );

  testWidgets('UPI pending shows Cancel Order', (tester) async {
    await pumpOrders(tester, [
      _orderJson(id: 'up', status: 'pending', paymentMethod: 'upi'),
    ]);
    expect(find.text('Cancel Order'), findsOneWidget);
  });

  testWidgets('UPI accepted unpaid shows Cancel Order', (tester) async {
    await pumpOrders(tester, [
      _orderJson(id: 'ua', status: 'accepted', paymentMethod: 'upi'),
    ]);
    expect(find.text('Cancel Order'), findsOneWidget);
    expect(find.text('Pay Now'), findsOneWidget);
  });

  testWidgets('UPI buyer_marked_paid hides Cancel Order', (tester) async {
    await pumpOrders(tester, [
      _orderJson(
        id: 'um',
        status: 'accepted',
        paymentMethod: 'upi',
        paymentStatus: 'buyer_marked_paid',
      ),
    ]);
    expect(find.text('Cancel Order'), findsNothing);
    expect(find.text('Awaiting Seller Confirmation'), findsOneWidget);
  });

  testWidgets('UPI seller_confirmed hides Cancel Order', (tester) async {
    await pumpOrders(tester, [
      _orderJson(
        id: 'uc',
        status: 'accepted',
        paymentMethod: 'upi',
        paymentStatus: 'seller_confirmed',
      ),
    ]);
    expect(find.text('Cancel Order'), findsNothing);
  });

  testWidgets('COD pending shows Cancel Order', (tester) async {
    await pumpOrders(tester, [
      _orderJson(id: 'cp', status: 'pending', paymentMethod: 'cash'),
    ]);
    expect(find.text('Cancel Order'), findsOneWidget);
  });

  testWidgets('COD accepted hides Cancel Order', (tester) async {
    await pumpOrders(tester, [
      _orderJson(id: 'ca', status: 'accepted', paymentMethod: 'cash'),
    ]);
    expect(find.text('Cancel Order'), findsNothing);
  });

  testWidgets('ready hides Cancel Order', (tester) async {
    await pumpOrders(tester, [_orderJson(id: 'rr', status: 'ready')]);
    expect(find.text('Cancel Order'), findsNothing);
  });

  testWidgets('completed hides Cancel Order', (tester) async {
    await pumpOrders(tester, [_orderJson(id: 'cc', status: 'completed')]);
    await tester.tap(find.textContaining('Past'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel Order'), findsNothing);
  });
}
