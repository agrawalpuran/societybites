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

  test('does not offer UPI collect intent on any platform', () {
    expect(
      shouldOfferUpiIntent(isWeb: false, platform: TargetPlatform.android),
      isFalse,
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
    expect(gpay.queryParameters.containsKey('mc'), isFalse);
    expect(gpay.queryParameters.containsKey('mode'), isFalse);
    expect(gpay.queryParameters.containsKey('tn'), isFalse);
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

  test('app launch omits merchant collect fields', () {
    final upi = buildUpiPaymentUri(
      upiId: 'seller.name@okaxis',
      payeeName: 'Sharma Snacks',
      amount: 245,
      transactionNote: 'SocietyBites Order SB-1023',
      transactionRef: 'SB-1023',
    );
    const target = UpiAppLaunchTarget(scheme: 'gpay', host: 'upi', path: '/pay');
    final launched = buildUpiAppLaunchUri(upiPayUri: upi, target: target);
    expect(launched.queryParameters.keys.toList(), ['pa', 'pn', 'am', 'cu']);
    expect(upiLaunchString(launched), 'gpay://upi/pay?pa=seller.name@okaxis&pn=Sharma%20Snacks&am=245.00&cu=INR');
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

    final ios = await getAvailableUpiApps(
      upi,
      canLaunch: (_) async => true,
      isWeb: false,
      platform: TargetPlatform.iOS,
    );
    expect(ios.map((app) => app.id), ['gpay', 'phonepe', 'paytm', 'bhim']);
    expect(ios.first.resolvedLaunchUri?.scheme, 'tez');
    expect(ios.first.resolvedLaunchUri?.query, isEmpty);
    expect(upiLaunchString(ios.first.resolvedLaunchUri!), 'tez://');

    final androidGpay = await getAvailableUpiApps(
      upi,
      canLaunch: (_) async => true,
      isWeb: false,
      platform: TargetPlatform.android,
    );
    expect(androidGpay.first.id, 'gpay');
    expect(androidGpay.first.resolvedLaunchUri?.scheme, 'gpay');
    expect(androidGpay.first.resolvedLaunchUri?.query, isEmpty);
    expect(upiLaunchString(androidGpay.first.resolvedLaunchUri!), 'gpay://');

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
      'gpay://upi/pay',
    );
    expect(
      androidGpayViaCollectHost.single.resolvedLaunchUri?.queryParameters,
      isEmpty,
    );
  });

  test('UPI shortcuts open the app without a collect URI', () {
    expect(shouldHandoffUpiCollect(platform: TargetPlatform.iOS), isTrue);
    expect(shouldHandoffUpiCollect(platform: TargetPlatform.android), isTrue);
    final iosTargets = launchTargetsFor(
      configuredUpiApps.first,
      platform: TargetPlatform.iOS,
    );
    expect(iosTargets.map((t) => t.scheme).toList(), ['tez', 'gpay']);
    expect(upiLaunchString(buildUpiAppOpenUri(iosTargets.first)), 'tez://');
    final androidTargets = launchTargetsFor(
      configuredUpiApps.first,
      platform: TargetPlatform.android,
    );
    expect(androidTargets.map((t) => t.scheme).toList(), ['gpay', 'tez']);
    expect(upiLaunchString(buildUpiAppOpenUri(androidTargets.first)), 'gpay://');
    expect(
      handoffProbeTargetsFor(
        configuredUpiApps.first,
        platform: TargetPlatform.android,
      ).map((t) => t.baseUrl),
      containsAll(['gpay://', 'gpay://upi/pay', 'tez://upi/pay']),
    );
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
