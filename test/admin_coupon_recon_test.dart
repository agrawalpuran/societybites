import 'package:flutter_test/flutter_test.dart';

import 'package:societybites/models/coupon.dart';

void main() {
  test('coupon seller payout report parses rows and seller totals', () {
    final report = AdminCouponSellerPayoutReport.fromJson({
      'totalSubsidy': 100,
      'rowCount': 1,
      'rows': [
        {
          'orderId': 'o1',
          'orderNumber': 'SE-1',
          'createdAt': '2026-01-15T10:00:00.000Z',
          'redeemedAt': '2026-01-15T10:01:00.000Z',
          'sellerId': 's1',
          'sellerName': 'Priya',
          'sellerPhone': '+919999999999',
          'couponCode': 'WELCOME100',
          'foodSubtotal': 500,
          'buyerPaid': 400,
          'subsidyAmount': 100,
          'orderStatus': 'completed',
          'paymentStatus': 'paid',
        },
      ],
      'bySeller': [
        {
          'sellerId': 's1',
          'sellerName': 'Priya',
          'subsidyTotal': 100,
          'orderCount': 1,
        },
      ],
    });

    expect(report.totalSubsidy, 100);
    expect(report.rows.single.subsidyAmount, 100);
    expect(report.bySeller.single.orderCount, 1);
  });
}
