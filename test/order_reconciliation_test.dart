import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/payment_screen.dart';
import 'package:societybites/services/api_service.dart';

const _initialOrder = Order(
  id: 'order-1',
  orderId: 'SB-1001',
  items: [],
  date: 'Today',
  status: 'accepted',
  statusStep: 1,
  orderTotal: 100,
  subtotal: 95,
  communityFee: 5,
  paymentMethod: 'upi',
  paymentStatus: 'pending',
);

Map<String, dynamic> _orderJson({
  String status = 'accepted',
  String paymentStatus = 'pending',
  double total = 100,
}) {
  const steps = {'pending': 0, 'accepted': 1, 'preparing': 2, 'ready': 3};
  return {
    'id': 'order-1',
    'orderId': 'SB-1001',
    'orderNumber': 'SB-1001',
    'items': <Object>[],
    'status': status,
    'statusStep': steps[status] ?? 0,
    'total': total,
    'subtotal': 95,
    'communityFee': 5,
    'paymentMethod': 'upi',
    'paymentStatus': paymentStatus,
    'createdAt': '2026-08-22T10:00:00.000Z',
  };
}

Future<Map<String, dynamic>> _paymentInfo(String _) async => {
  'sellerUpiId': 'seller@upi',
  'sellerUpiDisplayName': 'Test Seller',
};

Widget _paymentApp({
  required PaymentApiCall fetchOrder,
  PaymentApiCall? markPaid,
  UpiLauncher? launchUpi,
  Order order = _initialOrder,
  Duration pollInterval = const Duration(milliseconds: 20),
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Column(
          children: [
            const Text('Orders host'),
            ElevatedButton(
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    order: order,
                    fetchOrder: fetchOrder,
                    fetchPaymentInfo: _paymentInfo,
                    markPaid: markPaid,
                    launchUpi: launchUpi,
                    pollInterval: pollInterval,
                  ),
                ),
              ),
              child: const Text('Open payment'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _openPayment(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.tap(find.text('Open payment'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('ready-by request payload', () {
    test('preset durations stay durations', () {
      expect(buildOrderReadyTimePayload(readyInMinutes: 15), {
        'readyInMinutes': 15,
      });
      expect(buildOrderReadyTimePayload(readyInMinutes: 30), {
        'readyInMinutes': 30,
      });
    });

    test('custom local time is serialized as UTC', () {
      final local = DateTime(2026, 8, 22, 18);
      final payload = buildOrderReadyTimePayload(expectedReadyAt: local);
      final serialized = payload['expectedReadyAt'] as String;

      expect(serialized.endsWith('Z'), isTrue);
      expect(DateTime.parse(serialized).isUtc, isTrue);
      expect(DateTime.parse(serialized), local.toUtc());
    });
  });

  testWidgets('PaymentScreen immediately fetches the latest order', (
    tester,
  ) async {
    var fetchCount = 0;
    await _openPayment(
      tester,
      _paymentApp(
        fetchOrder: (_) async {
          fetchCount += 1;
          return _orderJson(paymentStatus: 'buyer_marked_paid');
        },
        pollInterval: const Duration(hours: 1),
      ),
    );

    expect(fetchCount, 1);
    expect(
      find.byKey(const ValueKey('awaiting-seller-confirmation')),
      findsOneWidget,
    );
  });

  testWidgets('mark paid reconciles to awaiting seller confirmation', (
    tester,
  ) async {
    var paymentStatus = 'pending';
    var markCount = 0;
    await _openPayment(
      tester,
      _paymentApp(
        fetchOrder: (_) async => _orderJson(paymentStatus: paymentStatus),
        markPaid: (_) async {
          markCount += 1;
          paymentStatus = 'buyer_marked_paid';
          return _orderJson(paymentStatus: paymentStatus);
        },
        pollInterval: const Duration(hours: 1),
      ),
    );

    final markPaidButton = find.text("I've Paid via UPI");
    await tester.ensureVisible(markPaidButton);
    await tester.tap(markPaidButton);
    await tester.pump();
    await tester.pump();

    expect(markCount, 1);
    expect(
      find.byKey(const ValueKey('awaiting-seller-confirmation')),
      findsOneWidget,
    );
  });

  testWidgets('polling updates payment status', (tester) async {
    var paymentStatus = 'pending';
    await _openPayment(
      tester,
      _paymentApp(
        fetchOrder: (_) async => _orderJson(paymentStatus: paymentStatus),
      ),
    );

    paymentStatus = 'buyer_marked_paid';
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('awaiting-seller-confirmation')),
      findsOneWidget,
    );
  });

  testWidgets('order status change returns to the existing orders progress', (
    tester,
  ) async {
    var status = 'accepted';
    var paymentStatus = 'pending';
    await _openPayment(
      tester,
      _paymentApp(
        fetchOrder: (_) async =>
            _orderJson(status: status, paymentStatus: paymentStatus),
      ),
    );

    status = 'preparing';
    paymentStatus = 'seller_confirmed';
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();

    expect(find.byType(PaymentScreen), findsNothing);
    expect(find.text('Orders host'), findsOneWidget);
  });

  testWidgets('polling stops after PaymentScreen is disposed', (tester) async {
    var fetchCount = 0;
    await _openPayment(
      tester,
      _paymentApp(
        fetchOrder: (_) async {
          fetchCount += 1;
          return _orderJson();
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    final countAfterDispose = fetchCount;
    await tester.pump(const Duration(milliseconds: 100));

    expect(fetchCount, countAfterDispose);
  });

  testWidgets('app resume triggers an immediate order refresh', (tester) async {
    var fetchCount = 0;
    await _openPayment(
      tester,
      _paymentApp(
        fetchOrder: (_) async {
          fetchCount += 1;
          return _orderJson();
        },
        pollInterval: const Duration(hours: 1),
      ),
    );
    final initialFetchCount = fetchCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(fetchCount, greaterThan(initialFetchCount));
  });

  testWidgets('UPI intent uses backend total without changing payment status', (
    tester,
  ) async {
    Uri? launchedUri;
    var markCount = 0;

    await _openPayment(
      tester,
      _paymentApp(
        order: const Order(
          id: 'order-1',
          orderId: 'SB-1001',
          items: [],
          date: 'Today',
          status: 'accepted',
          statusStep: 1,
          orderTotal: 245,
          subtotal: 220,
          communityFee: 0,
          deliveryCharge: 25,
          paymentMethod: 'upi',
          paymentStatus: 'pending',
        ),
        fetchOrder: (_) async => _orderJson(total: 245),
        markPaid: (_) async {
          markCount += 1;
          return _orderJson(total: 245, paymentStatus: 'buyer_marked_paid');
        },
        launchUpi: (uri) async {
          launchedUri = uri;
          return true;
        },
        pollInterval: const Duration(hours: 1),
      ),
    );

    final payButton = find.text('Pay ₹245 via UPI');
    await tester.ensureVisible(payButton);
    await tester.tap(payButton);
    await tester.pump();

    expect(launchedUri?.queryParameters['am'], '245.00');
    expect(launchedUri?.queryParameters['pa'], 'seller@upi');
    expect(launchedUri?.queryParameters['tn'], 'SocietyBites Order #SB-1001');
    expect(markCount, 0);
    expect(find.text("I've Paid via UPI"), findsOneWidget);
    expect(
      find.byKey(const ValueKey('awaiting-seller-confirmation')),
      findsNothing,
    );
  });

  testWidgets('failed UPI launch keeps QR fallback visible', (tester) async {
    await _openPayment(
      tester,
      _paymentApp(
        fetchOrder: (_) async => _orderJson(),
        launchUpi: (_) async => false,
        pollInterval: const Duration(hours: 1),
      ),
    );

    final payButton = find.text('Pay ₹100 via UPI');
    await tester.ensureVisible(payButton);
    await tester.tap(payButton);
    await tester.pump();

    expect(
      find.text(
        "We couldn't open a UPI app. Please use the QR code below to complete payment.",
      ),
      findsOneWidget,
    );
    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.text("I've Paid via UPI"), findsOneWidget);
  });
}
