import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/widgets/order_fulfilment_banner.dart';

Map<String, dynamic> _deliveryOrderJson() {
  return {
    'id': 'o-se-603040',
    'orderNumber': 'SE-603040',
    'status': 'accepted',
    'statusStep': 1,
    'paymentStatus': 'pending',
    'paymentMethod': 'upi',
    'total': 220,
    'subtotal': 220,
    'fulfilmentMethod': 'seller_delivery',
    'buyerName': 'Antara Mukherjee',
    'buyerPhone': '+917721874567',
    'buyerSocietyName': 'ND PASSION ELITE',
    'buyerSocietyAddress':
        'ND PASSION ELITE, Haralur Main Rd, Kudlu, Bengaluru, Karnataka 560068, India',
    'buyerCity': 'Bengaluru',
    'buyerBlock': 'B',
    'buyerFlatNumber': '701',
    'distanceKm': 1.2,
    'createdAt': '2026-10-23T07:43:06.031Z',
    'items': [
      {
        'quantity': 1,
        'unitPrice': 90,
        'listing': {
          'id': 'listing-1',
          'name': 'Amla candy',
          'sellerId': 'seller-1',
          'sellerName': 'CHASKA The Healthy Crunch',
          'price': 90,
        },
      },
    ],
  };
}

void main() {
  testWidgets('seller kitchen card opens buyer details sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerActiveOrderCard(
            order: Order.fromJson(_deliveryOrderJson()),
            onAction: (_, _, {deliveryCharge, deliveryCollectBy}) async {},
            onOrderUpdated: (_) {},
            onPaymentConfirmed: () async {},
            onReject: (_) async {},
            onReadyBy: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('seller-order-detail-sheet')), findsNothing);
    expect(find.byKey(const Key('seller-order-call-buyer')), findsNothing);

    await tester.tap(find.byKey(const Key('seller-order-open-details')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('seller-order-detail-sheet')), findsOneWidget);
    expect(find.text('Antara Mukherjee'), findsWidgets);
    expect(find.text('+917721874567'), findsOneWidget);
    expect(find.textContaining('Block B, Flat 701'), findsWidgets);
    expect(find.textContaining('Haralur Main Rd'), findsOneWidget);
    expect(find.byKey(const Key('seller-order-call-buyer')), findsOneWidget);
    expect(find.byKey(const Key('seller-order-open-maps')), findsOneWidget);
  });

  testWidgets('seller delivery banner keeps address and distance readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderFulfilmentBanner(
            order: Order.fromJson(_deliveryOrderJson()),
            isSellerView: true,
          ),
        ),
      ),
    );
    expect(
      find.textContaining('ND PASSION ELITE · Block B, Flat 701'),
      findsOneWidget,
    );
    expect(find.textContaining('~1.2 km'), findsOneWidget);
  });
}
