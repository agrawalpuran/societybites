import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/payment_screen.dart';

Order _order() {
  return Order(
    id: 'order-1',
    orderId: 'SE-1001',
    items: [
      OrderLineItem(
        quantity: 1,
        unitPrice: 90,
        food: FoodItem(
          id: 'f1',
          name: 'Samosa',
          sellerId: 's1',
          sellerName: 'Chef',
          block: 'A',
          price: 90,
          rating: 4,
          pickupTime: '10m',
          description: '',
          icon: Icons.restaurant,
          bgColor: const Color(0xFFF0F2F1),
          sellerUpiId: 'seller@upi',
        ),
      ),
    ],
    date: 'Today',
    status: 'accepted',
    statusStep: 1,
    orderTotal: 100,
    subtotal: 90,
    communityFee: 10,
    paymentMethod: 'upi',
    paymentStatus: 'pending',
  );
}

Map<String, dynamic> _orderJson() {
  return {
    'id': 'order-1',
    'orderId': 'SE-1001',
    'orderNumber': 'SE-1001',
    'items': <Object>[],
    'status': 'accepted',
    'statusStep': 1,
    'total': 100,
    'subtotal': 90,
    'communityFee': 10,
    'paymentMethod': 'upi',
    'paymentStatus': 'pending',
  };
}

void main() {
  testWidgets('direct UPI still copies the seller UPI ID', (tester) async {
    String? copied;
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PaymentScreen(
          order: _order(),
          fetchOrder: (_) async => _orderJson(),
          fetchPaymentInfo: (_) async => {
            'sellerUpiId': 'seller@upi',
            'sellerUpiDisplayName': 'Chef',
          },
          pollInterval: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("I've Paid via UPI"), findsOneWidget);
    expect(find.text('seller@upi'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('copy-upi-id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('copy-upi-id')));
    await tester.pump();
    expect(copied, 'seller@upi');
  });

  testWidgets('Cashfree checkout does not launch the seller UPI link', (
    tester,
  ) async {
    Uri? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentScreen(
          order: _order(),
          fetchOrder: (_) async => _orderJson(),
          fetchPaymentInfo: (_) async => {
            'sellerUpiId': 'seller@upi',
            'sellerUpiDisplayName': 'Chef',
          },
          startCheckout: (_) async => {
            'paymentProvider': 'cashfree',
            'paymentStatus': 'pending',
            'gatewayUpiLink': 'https://sandbox.cashfree.com/pg/upi/test-link',
            'gatewayQrPayload': 'upi://pay?pa=order@cashfree&am=100',
          },
          launchUpi: (uri) async {
            launched = uri;
            return true;
          },
          pollInterval: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text("I've Paid via UPI"), findsNothing);
    expect(find.text('seller@upi'), findsNothing);
    expect(find.text('Pay with Cashfree'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('upi://pay?pa=order@cashfree&am=100'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Open UPI app'));
    await tester.pump();
    expect(launched.toString(), contains('cashfree.com'));
    expect(launched.toString(), isNot(contains('seller@upi')));
  });
}
