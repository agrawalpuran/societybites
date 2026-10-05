import 'package:flutter_test/flutter_test.dart';

import 'package:societybites/models/coupon.dart';

void main() {
  test('coupon reason messages are buyer friendly', () {
    expect(couponReasonMessage('COUPON_EXPIRED'), 'This coupon has expired');
    expect(couponReasonMessage('MINIMUM_ORDER_NOT_MET'),
        'Your order does not meet the minimum for this coupon');
  });

  test('coupon quote parses validation payload', () {
    final quote = CouponQuote.fromJson({
      'code': 'WELCOME100',
      'discountAmount': 100,
      'orderSubtotal': 500,
      'buyerPayable': 400,
      'sellerGrossAmount': 500,
      'societyEatsSubsidy': 100,
    });
    expect(quote.code, 'WELCOME100');
    expect(quote.sellerGrossAmount, 500);
    expect(quote.societyEatsSubsidy, 100);
  });
}
