import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/admin/admin_order_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('order drill-down shows buyer and seller address', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AdminOrderDetailScreen(
          orderId: 'order-1',
          loadOrder: (_) async => {
            'id': 'order-1',
            'orderNumber': 'SE-100001',
            'status': 'ready',
            'type': 'regular',
            'paymentMethod': 'upi',
            'paymentStatus': 'confirmed',
            'subtotal': 240,
            'communityFee': 0,
            'deliveryCharge': 20,
            'total': 260,
            'fulfilmentMethod': 'seller_delivery',
            'fulfilmentNotes': 'Leave with security',
            'createdAt': '2026-10-23T08:00:00.000Z',
            'updatedAt': '2026-10-23T09:00:00.000Z',
            'society': {
              'name': 'Lake View',
              'address': '4 Lake Road',
              'city': 'Pune',
              'state': 'Maharashtra',
              'pincode': '411002',
            },
            'buyer': {
              'name': 'Ravi Shah',
              'phone': '919800000002',
              'role': 'buyer',
              'flat': {'block': 'A', 'flatNumber': '1204', 'floor': 12},
              'society': {
                'name': 'Lake View',
                'address': '4 Lake Road',
                'city': 'Pune',
                'state': 'Maharashtra',
                'pincode': '411002',
              },
            },
            'sellers': [
              {
                'name': 'Anita Kitchen',
                'phone': '919800000001',
                'role': 'seller',
                'upiId': 'anita@upi',
                'upiDisplayName': 'Anita',
                'fulfilmentMode': 'BOTH',
                'hideFlatNumber': true,
                'flat': {'block': 'B', 'flatNumber': '88', 'floor': 8},
                'society': {
                  'name': 'Palm Heights',
                  'address': '12 Palm Drive',
                  'city': 'Pune',
                  'state': 'Maharashtra',
                  'pincode': '411001',
                },
              },
            ],
            'items': [
              {
                'quantity': 2,
                'unitPrice': 120,
                'lineTotal': 240,
                'listing': {
                  'name': 'Paneer tikka',
                  'sellerName': 'Anita Kitchen',
                  'pickupLocation': 'My Home (Verified)',
                },
              },
            ],
            'coupon': {'code': 'WELCOME', 'discountAmount': 40},
            'timeline': {'createdAt': '2026-10-23T08:00:00.000Z'},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('#SE-100001'), findsOneWidget);
    expect(find.text('Ravi Shah'), findsOneWidget);
    expect(find.text('919800000002'), findsOneWidget);
    expect(find.textContaining('Flat 1204'), findsOneWidget);
    expect(find.textContaining('4 Lake Road'), findsWidgets);
    expect(find.text('Anita Kitchen'), findsWidgets);
    expect(find.text('919800000001'), findsOneWidget);
    expect(find.text('anita@upi'), findsOneWidget);
    expect(find.textContaining('Flat 88'), findsOneWidget);
    expect(find.textContaining('12 Palm Drive'), findsOneWidget);
    expect(find.textContaining('hidden from buyers'), findsOneWidget);
    expect(find.text('Paneer tikka'), findsOneWidget);
    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.text('Leave with security'), findsOneWidget);
  });
}
