import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/upi_account_type.dart';
import 'package:societybites/services/upi_payment_service.dart';

void main() {
  test('builds an encoded standard UPI payment URI', () {
    final uri = buildUpiPaymentUri(
      upiId: 'seller.name@okaxis',
      payeeName: 'Sharma Snacks & More',
      amount: 245,
      transactionNote: 'SocietyEats Order SB-1023',
      transactionRef: 'SB-1023',
    );

    expect(uri.scheme, 'upi');
    expect(uri.host, 'pay');
    expect(uri.queryParameters, {
      'pa': 'seller.name@okaxis',
      'pn': 'Sharma Snacks & More',
      'am': '245.00',
      'cu': 'INR',
      'tn': 'SocietyEats Order SB-1023',
    });
    final encoded = upiLaunchString(uri);
    expect(encoded, contains('Sharma%20Snacks%20%26%20More'));
    expect(encoded, isNot(contains('Sharma+')));
    expect(encoded, contains('tn=SocietyEats%20Order%20SB-1023'));
    expect(encoded, isNot(contains('tr=')));
    expect(encoded, isNot(contains('mc=')));
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
        transactionNote: 'SocietyEats Order SB1023',
      ),
      throwsArgumentError,
    );
    expect(
      () => buildUpiPaymentUri(
        upiId: 'seller@upi',
        payeeName: 'Seller',
        amount: 0,
        transactionNote: 'SocietyEats Order SB1023',
      ),
      throwsArgumentError,
    );
  });

  test('does not offer an in-app UPI intent for any seller account', () {
    expect(
      shouldOfferUpiIntent(isWeb: false, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      shouldOfferUpiIntent(
        isWeb: false,
        platform: TargetPlatform.android,
        accountType: UpiAccountType.merchant,
      ),
      isFalse,
    );
    expect(
      shouldOfferUpiIntent(
        isWeb: false,
        platform: TargetPlatform.iOS,
        accountType: UpiAccountType.merchant,
      ),
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
      transactionNote: 'SocietyEats Order SB-1023',
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
    expect(gpay.queryParameters.containsKey('am'), isFalse);
    expect(gpay.queryParameters['tn'], 'SocietyEats Order SB-1023');
    expect(gpay.queryParameters.containsKey('tr'), isFalse);
    expect(gpay.queryParameters.containsKey('mc'), isFalse);
    expect(gpay.queryParameters.containsKey('mode'), isFalse);
    expect(upiLaunchString(gpay), startsWith('gpay://upi/pay?'));
    expect(upiLaunchString(gpay), contains('pn=Sharma%20Snacks'));
    expect(upiLaunchString(gpay), isNot(contains('SocietyBites')));
    expect(upiLaunchString(gpay), isNot(contains('mc=')));
    expect(upiLaunchString(gpay), isNot(contains('tr=')));
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

  test('personal app launch omits merchant collect fields', () {
    final upi = buildUpiPaymentUri(
      upiId: 'seller.name@okaxis',
      payeeName: 'Sharma Snacks',
      amount: 245,
      transactionNote: 'SocietyEats Order SB-1023',
      transactionRef: 'SB-1023',
    );
    const target = UpiAppLaunchTarget(scheme: 'gpay', host: 'upi', path: '/pay');
    final launched = buildUpiAppLaunchUri(upiPayUri: upi, target: target);
    expect(launched.queryParameters.keys.toSet(), {'pa', 'pn', 'cu', 'tn'});
    expect(launched.queryParameters.containsKey('am'), isFalse);
    expect(upiLaunchString(launched), 'gpay://upi/pay?pa=seller.name@okaxis&pn=Sharma%20Snacks&tn=SocietyEats%20Order%20SB-1023&cu=INR');
  });

  test('merchant app launch keeps the note and drops the transaction ref', () {
    final upi = buildUpiPaymentUri(
      upiId: 'shop@okbizaxis',
      payeeName: 'Sharma Snacks',
      amount: 245,
      transactionNote: 'SocietyEats Order SB-1023',
      transactionRef: 'SB-1023',
    );
    const target = UpiAppLaunchTarget(scheme: 'gpay', host: 'upi', path: '/pay');
    final noted = buildUpiAppLaunchUri(
      upiPayUri: upi,
      target: target,
      accountType: UpiAccountType.merchant,
      transactionNote: 'SB-1023',
    );
    expect(noted.queryParameters.keys.toSet(), {'pa', 'pn', 'cu', 'tn'});
    expect(noted.queryParameters['tn'], 'SB-1023');
    expect(noted.queryParameters.containsKey('am'), isFalse);
    expect(noted.queryParameters.containsKey('tr'), isFalse);
    expect(upiLaunchString(noted), isNot(contains('am=')));
    expect(shouldHandoffUpiCollect(
      platform: TargetPlatform.android,
      accountType: UpiAccountType.merchant,
    ), isFalse);
  });

  test('GPay, PhonePe, and Paytm open the UPI ID with the order note and no amount', () async {
    final upi = buildUpiPaymentUri(
      upiId: 'seller@oksbi',
      payeeName: 'Sharma Snacks',
      amount: 245,
      transactionNote: 'SocietyEats Order SB-1023',
      transactionRef: 'SB-1023',
    );

    final apps = await getAvailableUpiApps(
      upi,
      canLaunch: (_) async => true,
      isWeb: false,
      platform: TargetPlatform.android,
      accountType: UpiAccountType.merchant,
    );
    expect(apps.map((app) => app.id), ['gpay', 'phonepe', 'paytm', 'bhim']);
    expect(upiLaunchString(apps[0].resolvedLaunchUri!), startsWith('gpay://upi/pay?'));
    expect(upiLaunchString(apps[1].resolvedLaunchUri!), startsWith('phonepe://pay?'));
    expect(upiLaunchString(apps[2].resolvedLaunchUri!), startsWith('paytmmp://pay?'));
    for (final app in apps) {
      expect(app.resolvedLaunchUri!.queryParameters['pa'], 'seller@oksbi');
      expect(app.resolvedLaunchUri!.queryParameters['tn'], 'SocietyEats Order SB-1023');
      expect(app.resolvedLaunchUri!.queryParameters.containsKey('am'), isFalse);
      expect(app.resolvedLaunchUri!.queryParameters.containsKey('tr'), isFalse);
    }
  });

  test('getAvailableUpiApps hides apps that cannot launch', () async {
    final upi = buildUpiPaymentUri(
      upiId: 'seller@upi',
      payeeName: 'Seller',
      amount: 10,
      transactionNote: 'SocietyEats Order SB1',
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

    final ios = await getAvailableUpiApps(
      upi,
      canLaunch: (_) async => true,
      isWeb: false,
      platform: TargetPlatform.iOS,
    );
    expect(ios.map((app) => app.id), ['gpay', 'phonepe', 'paytm', 'bhim']);
    expect(ios.first.resolvedLaunchUri?.scheme, 'tez');
    expect(ios.first.resolvedLaunchUri?.host, 'upi');
    expect(ios.first.resolvedLaunchUri?.queryParameters['pa'], 'seller@upi');
    expect(ios.first.resolvedLaunchUri?.queryParameters.containsKey('am'), isFalse);

    final androidGpay = await getAvailableUpiApps(
      upi,
      canLaunch: (_) async => true,
      isWeb: false,
      platform: TargetPlatform.android,
    );
    expect(androidGpay.first.id, 'gpay');
    expect(androidGpay.first.resolvedLaunchUri?.scheme, 'gpay');
    expect(androidGpay.first.resolvedLaunchUri?.host, 'upi');
    expect(androidGpay.first.resolvedLaunchUri?.queryParameters['pa'], 'seller@upi');
    expect(androidGpay.first.resolvedLaunchUri?.queryParameters.containsKey('am'), isFalse);

    final androidGpayViaCollectHost = await getAvailableUpiApps(
      upi,
      canLaunch: (uri) async =>
          uri.scheme == 'gpay' && uri.host == 'upi' && uri.path == '/pay',
      isWeb: false,
      platform: TargetPlatform.android,
    );
    expect(androidGpayViaCollectHost.map((app) => app.id), ['gpay']);
    expect(
      upiLaunchString(androidGpayViaCollectHost.single.resolvedLaunchUri!),
      startsWith('gpay://upi/pay?'),
    );
    expect(
      androidGpayViaCollectHost.single.resolvedLaunchUri?.queryParameters['pa'],
      'seller@upi',
    );
    expect(
      androidGpayViaCollectHost.single.resolvedLaunchUri?.queryParameters.containsKey('am'),
      isFalse,
    );
  });

  test('app icons use each app pay screen', () {
    expect(shouldHandoffUpiCollect(platform: TargetPlatform.iOS), isFalse);
    expect(shouldHandoffUpiCollect(platform: TargetPlatform.android), isFalse);
    final iosTargets = launchTargetsFor(
      configuredUpiApps.first,
      platform: TargetPlatform.iOS,
    );
    expect(iosTargets.map((t) => t.baseUrl).toList(), ['tez://upi/pay', 'gpay://upi/pay']);
    final androidTargets = launchTargetsFor(
      configuredUpiApps.first,
      platform: TargetPlatform.android,
    );
    expect(androidTargets.first.baseUrl, 'gpay://upi/pay');
  });

  test('sanitizes UPI transaction references', () {
    expect(sanitizeUpiTransactionRef('SB-307454'), 'SB307454');
    expect(sanitizeUpiTransactionRef(''), 'SBORDER');
    expect(
      uniqueUpiTransactionRef(
        'SB-1023',
        now: DateTime.utc(2026, 9, 29, 5),
      ),
      'SB1023${DateTime.utc(2026, 9, 29, 5).millisecondsSinceEpoch}',
    );
  });
}
