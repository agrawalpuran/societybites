import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/screens/orders_screen.dart';
import 'package:societybites/screens/payment_screen.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/widgets/listing_image.dart';
import 'package:societybites/widgets/order_call_button.dart';

Map<String, dynamic> _orderJson({
  required String status,
  String paymentMethod = 'upi',
  String paymentStatus = 'pending',
  bool sellerCanDecline = false,
  String? rejectReason,
  bool refundDue = false,
  bool canRevealBuyerPhone = false,
  bool canRevealSellerPhone = false,
}) {
  return {
    'id': 'o1',
    'orderNumber': 'SB-o1',
    'status': status,
    'statusStep': BuyerOrderLifecycle.progressStep(status),
    'sellerCanDecline': sellerCanDecline,
    'paymentStatus': paymentStatus,
    'paymentMethod': paymentMethod,
    'buyerPhone': '+919845154070',
    'buyerName': 'Puran',
    'canRevealBuyerPhone': canRevealBuyerPhone,
    'canRevealSellerPhone': canRevealSellerPhone,
    'total': 120,
    'subtotal': 115,
    'communityFee': 5,
    'rejectReason': rejectReason,
    'refundDue': refundDue,
    'createdAt': '2026-09-18T10:00:00.000Z',
    'items': [
      {
        'quantity': 1,
        'unitPrice': 115,
        'listing': {
          'id': 'listing-1',
          'name': 'Paneer',
          'sellerId': 'seller-1',
          'sellerName': 'Anita',
          'price': 115,
          'imageUrl': 'https://example.com/paneer.jpg',
        },
      },
    ],
  };
}

Finder get _callActions => find.byWidgetPredicate((widget) {
      if (widget is Icon) {
        return widget.icon == Icons.phone ||
            widget.icon == Icons.phone_rounded ||
            widget.icon == Icons.call ||
            widget.icon == Icons.call_rounded;
      }
      return false;
    });

Widget _sellerCard(Order order, {bool rejectBusy = false}) {
  return MaterialApp(
    home: Scaffold(
      body: SellerActiveOrderCard(
        order: order,
        onAction: (_, _, {deliveryCharge, deliveryCollectBy}) async {},
        onOrderUpdated: (_) {},
        onPaymentConfirmed: () async {},
        onReject: (_) async {},
        onReadyBy: (_) async {},
        rejectBusy: rejectBusy,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UPI payment pending seller card has no call button', (tester) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(
          _orderJson(status: 'accepted', paymentStatus: 'pending'),
        ),
      ),
    );
    expect(find.text('Payment Pending'), findsOneWidget);
    expect(_callActions, findsNothing);
  });

  testWidgets('UPI buyer-marked-paid seller card has no call button', (tester) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(
          _orderJson(status: 'accepted', paymentStatus: 'buyer_marked_paid'),
        ),
      ),
    );
    expect(find.text('BUYER PAID'), findsOneWidget);
    expect(find.text('Order Accepted'), findsNothing);
    expect(find.textContaining('buyer marked paid'), findsNothing);
    expect(_callActions, findsNothing);
  });

  testWidgets('Mark Ready shows Complete before parent order list updates', (
    tester,
  ) async {
    final seed = Order.fromJson(
      _orderJson(status: 'accepted', paymentStatus: 'seller_confirmed'),
    );
    var held = seed;
    final completer = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SellerActiveOrderCard(
                order: held,
                onAction: (_, _, {deliveryCharge, deliveryCollectBy}) =>
                    completer.future,
                onOrderUpdated: (updated) => setState(() => held = updated),
                onPaymentConfirmed: () async {},
                onReject: (_) async {},
                onReadyBy: (_) async {},
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Mark Ready'), findsOneWidget);
    await tester.tap(find.text('Mark Ready'));
    await tester.pump();

    expect(find.text('Complete Order'), findsOneWidget);
    expect(find.text('Mark Ready'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('UPI payment confirmed seller card has no call button', (tester) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(
          _orderJson(status: 'accepted', paymentStatus: 'seller_confirmed'),
        ),
      ),
    );
    expect(find.text('Mark Ready'), findsOneWidget);
    expect(_callActions, findsNothing);
  });

  testWidgets('COD seller card has no call button', (tester) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(
          _orderJson(
            status: 'accepted',
            paymentMethod: 'cash',
            paymentStatus: 'pending',
          ),
        ),
      ),
    );
    expect(find.text('Mark Ready'), findsOneWidget);
    expect(_callActions, findsNothing);
  });

  testWidgets('buyer orders screen has no call action', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [
            _orderJson(status: 'accepted', paymentStatus: 'pending'),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(_callActions, findsNothing);
  });

  testWidgets('single-item seller card shows the listing photo', (tester) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(
          _orderJson(status: 'accepted', paymentStatus: 'pending'),
        ),
      ),
    );
    expect(find.byType(ListingImage), findsOneWidget);
  });

  testWidgets('buyer payment screen has no call action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentScreen(
          order: Order.fromJson(_orderJson(status: 'accepted')),
          fetchPaymentInfo: (_) async => {
            'sellerUpiId': 'anita@upi',
            'paymentStatus': 'pending',
            'paymentMethod': 'upi',
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(_callActions, findsNothing);
  });

  testWidgets('pending order has an enabled Reject button', (tester) async {
    await tester.pumpWidget(
      _sellerCard(Order.fromJson(_orderJson(status: 'pending'))),
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('seller-reject-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('rejected order hides decline and shows rejection summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(
          _orderJson(
            status: 'rejected',
            rejectReason: 'Not enough time\nApologies had to step out',
            refundDue: true,
            paymentStatus: 'buyer_marked_paid',
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('seller-reject-button')), findsNothing);
    expect(find.text('ORDER REJECTED'), findsOneWidget);
    expect(find.textContaining('Not enough time'), findsOneWidget);
    expect(find.byKey(const Key('seller-refund-due')), findsOneWidget);
  });

  testWidgets('accepted order offers Can\'t fulfil to the seller', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(_orderJson(status: 'accepted', sellerCanDecline: true)),
      ),
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('seller-reject-button')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text("Can't fulfil"), findsOneWidget);
  });

  testWidgets('Reject is disabled while a rejection is in progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(_orderJson(status: 'pending')),
        rejectBusy: true,
      ),
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('seller-reject-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('paid kitchen order shows Call next to Message Buyer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sellerCard(
        Order.fromJson(
          _orderJson(
            status: 'accepted',
            paymentStatus: 'seller_confirmed',
            canRevealBuyerPhone: true,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('order-call-button')), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Message Buyer'), findsOneWidget);
  });

  testWidgets('paid buyer order shows Call next to Message Seller', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [
            _orderJson(
              status: 'ready',
              paymentStatus: 'seller_confirmed',
              canRevealSellerPhone: true,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('order-call-button')), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Message Seller'), findsOneWidget);
  });

  testWidgets('Call on buyer order opens the phone dialer', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
    String? dialed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderContactActions(
            order: Order.fromJson(
              _orderJson(
                status: 'ready',
                paymentStatus: 'seller_confirmed',
                canRevealSellerPhone: true,
              ),
            ),
            isSellerView: false,
            revealPhone: (_) async => '+919845154070',
            dialPhone: (phone) async {
              dialed = phone;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('order-call-button')));
    await tester.pumpAndSettle();
    expect(find.text('Call seller?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Call'));
    await tester.pumpAndSettle();
    expect(dialed, '+919845154070');
  });
}
