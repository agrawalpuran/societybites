import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/services/upi_payment_service.dart';

void main() {
  test('builds an encoded standard UPI payment URI', () {
    final uri = buildUpiPaymentUri(
      upiId: 'seller.name@okaxis',
      payeeName: 'Sharma Snacks & More',
      amount: 245,
      transactionNote: 'SocietyBites Order SB-1023',
      transactionRef: 'SB-1023',
    );

    expect(uri.scheme, 'upi');
    expect(uri.host, 'pay');
    expect(uri.queryParameters, {
      'pa': 'seller.name@okaxis',
      'pn': 'Sharma Snacks & More',
      'am': '245.00',
      'cu': 'INR',
      'tr': 'SB1023',
      'tn': 'SocietyBites Order SB-1023',
    });
    final encoded = upiLaunchString(uri);
    expect(encoded, contains('Sharma%20Snacks%20%26%20More'));
    expect(encoded, isNot(contains('Sharma+')));
    expect(encoded, contains('tn=SocietyBites%20Order%20SB-1023'));
    expect(encoded, contains('tr=SB1023'));
    expect(uri.queryParameters.keys, hasLength(6));
  });

  test('rejects missing or invalid payment values', () {
    expect(isValidUpiId('seller@upi'), isTrue);
    expect(isValidUpiId('not-a-upi-id'), isFalse);
    expect(
      () => buildUpiPaymentUri(
        upiId: 'invalid',
        payeeName: 'Seller',
        amount: 245,
        transactionNote: 'SocietyBites Order SB1023',
      ),
      throwsArgumentError,
    );
    expect(
      () => buildUpiPaymentUri(
        upiId: 'seller@upi',
        payeeName: 'Seller',
        amount: 0,
        transactionNote: 'SocietyBites Order SB1023',
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

  test('offers UPI app shortcuts on Android and iOS only', () {
    expect(
      shouldOfferUpiAppShortcuts(isWeb: false, platform: TargetPlatform.android),
      isTrue,
    );
    expect(
      shouldOfferUpiAppShortcuts(isWeb: false, platform: TargetPlatform.iOS),
      isTrue,
    );
    expect(
      shouldOfferUpiAppShortcuts(isWeb: true, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      shouldOfferUpiAppShortcuts(isWeb: false, platform: TargetPlatform.fuchsia),
      isFalse,
    );
  });

  test('app launch URIs keep QR query parameters', () {
    final upi = buildUpiPaymentUri(
      upiId: 'seller.name@okaxis',
      payeeName: 'Sharma Snacks',
      amount: 245,
      transactionNote: 'SocietyBites Order SB-1023',
      transactionRef: 'SB-1023',
    );
    expect(upi.scheme, 'upi');
    expect(upi.host, 'pay');

    final gpay = buildUpiAppLaunchUri(
      upiPayUri: upi,
      target: const UpiAppLaunchTarget(scheme: 'gpay', host: 'upi', path: '/pay'),
    );
    expect(gpay.scheme, 'gpay');
    expect(gpay.host, 'upi');
    expect(gpay.path, '/pay');
    expect(gpay.queryParameters['pa'], upi.queryParameters['pa']);
    expect(gpay.queryParameters['am'], '245.00');
    expect(gpay.queryParameters.containsKey('tr'), isFalse);
    expect(upiLaunchString(gpay), startsWith('gpay://upi/pay?'));
    expect(upiLaunchString(gpay), contains('SocietyBites%20Order%20SB-1023'));
    expect(upiLaunchString(gpay), isNot(contains('+')));

    final phonepe = buildUpiAppLaunchUri(
      upiPayUri: upi,
      target: const UpiAppLaunchTarget(scheme: 'phonepe', host: 'upi', path: '/pay'),
    );
    expect(phonepe.scheme, 'phonepe');
    expect(phonepe.host, 'upi');
    expect(phonepe.path, '/pay');
    expect(upiLaunchString(phonepe), startsWith('phonepe://upi/pay?'));

    final paytm = buildUpiAppLaunchUri(
      upiPayUri: upi,
      target: const UpiAppLaunchTarget(scheme: 'paytm', host: 'upi', path: '/pay'),
    );
    expect(upiLaunchString(paytm), startsWith('paytm://upi/pay?'));
    expect(paytm.queryParameters['pa'], upi.queryParameters['pa']);

    final bhim = buildUpiAppLaunchUri(
      upiPayUri: upi,
      target: const UpiAppLaunchTarget(scheme: 'bhim', host: 'upi', path: '/pay'),
    );
    expect(upiLaunchString(bhim), startsWith('bhim://upi/pay?'));
  });

  test('getAvailableUpiApps hides apps that cannot launch', () async {
    final upi = buildUpiPaymentUri(
      upiId: 'seller@upi',
      payeeName: 'Seller',
      amount: 10,
      transactionNote: 'SocietyBites Order SB1',
      transactionRef: 'SB-1',
    );

    final none = await getAvailableUpiApps(
      upi,
      canLaunch: (_) async => false,
      isWeb: false,
      platform: TargetPlatform.android,
    );
    expect(none, isEmpty);

    final web = await getAvailableUpiApps(
      upi,
      canLaunch: (_) async => true,
      isWeb: true,
      platform: TargetPlatform.android,
    );
    expect(web, isEmpty);

    final onlyPhonePe = await getAvailableUpiApps(
      upi,
      canLaunch: (uri) async => uri.scheme == 'phonepe',
      isWeb: false,
      platform: TargetPlatform.iOS,
    );
    expect(onlyPhonePe.map((app) => app.id), ['phonepe']);
    expect(onlyPhonePe.single.resolvedLaunchUri?.scheme, 'phonepe');
    expect(onlyPhonePe.single.resolvedLaunchUri?.host, 'upi');
    expect(
      upiLaunchString(onlyPhonePe.single.resolvedLaunchUri!),
      startsWith('phonepe://upi/pay?'),
    );
  });

  test('sanitizes UPI transaction references', () {
    expect(sanitizeUpiTransactionRef('SB-307454'), 'SB307454');
    expect(sanitizeUpiTransactionRef(''), 'SBORDER');
  });
}
