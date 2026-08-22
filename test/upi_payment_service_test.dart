import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/services/upi_payment_service.dart';

void main() {
  test('builds an encoded standard UPI payment URI', () {
    final uri = buildUpiPaymentUri(
      upiId: 'seller.name@okaxis',
      payeeName: 'Sharma Snacks & More',
      amount: 245,
      transactionNote: 'SocietyBites Order #SB1023',
    );

    expect(uri.scheme, 'upi');
    expect(uri.host, 'pay');
    expect(uri.queryParameters, {
      'pa': 'seller.name@okaxis',
      'pn': 'Sharma Snacks & More',
      'am': '245.00',
      'cu': 'INR',
      'tn': 'SocietyBites Order #SB1023',
    });
    expect(uri.toString(), contains('Sharma+Snacks+%26+More'));
    expect(uri.toString(), contains('%23SB1023'));
    expect(uri.queryParameters.keys, hasLength(5));
  });

  test('rejects missing or invalid payment values', () {
    expect(isValidUpiId('seller@upi'), isTrue);
    expect(isValidUpiId('not-a-upi-id'), isFalse);
    expect(
      () => buildUpiPaymentUri(
        upiId: 'invalid',
        payeeName: 'Seller',
        amount: 245,
        transactionNote: 'SocietyBites Order #SB1023',
      ),
      throwsArgumentError,
    );
    expect(
      () => buildUpiPaymentUri(
        upiId: 'seller@upi',
        payeeName: 'Seller',
        amount: 0,
        transactionNote: 'SocietyBites Order #SB1023',
      ),
      throwsArgumentError,
    );
  });

  test('offers UPI intent only on native Android', () {
    expect(
      shouldOfferUpiIntent(isWeb: false, platform: TargetPlatform.android),
      isTrue,
    );
    expect(
      shouldOfferUpiIntent(isWeb: true, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      shouldOfferUpiIntent(isWeb: false, platform: TargetPlatform.iOS),
      isFalse,
    );
  });
}
