import 'package:flutter/foundation.dart';

bool shouldOfferUpiIntent({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb && platform == TargetPlatform.android;
}

bool shouldOfferUpiAppShortcuts({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
}

class UpiAppLaunchTarget {
  const UpiAppLaunchTarget({
    required this.scheme,
    this.host,
    this.path = '',
  });

  final String scheme;
  final String? host;
  final String path;

  String get baseUrl {
    final authority = host ?? '';
    if (authority.isEmpty) return '$scheme:$path';
    return '$scheme://$authority$path';
  }
}

class UpiAppOption {
  const UpiAppOption({
    required this.id,
    required this.displayName,
    required this.launchTargets,
    this.resolvedLaunchUri,
  });

  final String id;
  final String displayName;
  final List<UpiAppLaunchTarget> launchTargets;
  final Uri? resolvedLaunchUri;

  UpiAppOption withLaunchUri(Uri uri) {
    return UpiAppOption(
      id: id,
      displayName: displayName,
      launchTargets: launchTargets,
      resolvedLaunchUri: uri,
    );
  }
}

/// Preferred launch targets. Query always comes from [buildUpiPayQuery].
///
/// iOS GPay/PhonePe only honor `://upi/pay`. `phonepe://pay` opens PhonePe's
/// gallery-QR flow (₹2,000 cap / dismiss), not a normal collect.
const configuredUpiApps = <UpiAppOption>[
  UpiAppOption(
    id: 'gpay',
    displayName: 'GPay',
    launchTargets: [
      UpiAppLaunchTarget(scheme: 'gpay', host: 'upi', path: '/pay'),
      UpiAppLaunchTarget(scheme: 'tez', host: 'upi', path: '/pay'),
    ],
  ),
  UpiAppOption(
    id: 'phonepe',
    displayName: 'PhonePe',
    launchTargets: [
      UpiAppLaunchTarget(scheme: 'phonepe', host: 'upi', path: '/pay'),
      UpiAppLaunchTarget(scheme: 'phonepe', host: 'pay'),
    ],
  ),
  UpiAppOption(
    id: 'paytm',
    displayName: 'Paytm',
    launchTargets: [
      UpiAppLaunchTarget(scheme: 'paytm', host: 'upi', path: '/pay'),
      UpiAppLaunchTarget(scheme: 'paytmmp', host: 'upi', path: '/pay'),
      UpiAppLaunchTarget(scheme: 'paytmmp', host: 'pay'),
      UpiAppLaunchTarget(scheme: 'paytm', host: 'pay'),
    ],
  ),
  UpiAppOption(
    id: 'bhim',
    displayName: 'BHIM',
    launchTargets: [
      UpiAppLaunchTarget(scheme: 'bhim', host: 'upi', path: '/pay'),
      UpiAppLaunchTarget(scheme: 'bhim', host: 'pay'),
    ],
  ),
];

/// NPCI wants `%20` for spaces. Dart's [Uri.queryParameters] emits `+`, which
/// GPay iOS shows literally (`SocietyBites+Order+SB-993150`) and can fail.
String encodeUpiQueryValue(String value) => Uri.encodeComponent(value);

String buildUpiPayQuery({
  required String upiId,
  required String payeeName,
  required double amount,
  required String transactionNote,
  String? transactionRef,
  bool includeTransactionRef = true,
}) {
  final normalizedUpiId = upiId.trim();
  final normalizedPayeeName = payeeName.trim();
  final normalizedNote = transactionNote.trim();
  final normalizedRef = sanitizeUpiTransactionRef(
    (transactionRef ?? transactionNote).trim(),
  );

  if (!isValidUpiId(normalizedUpiId)) {
    throw ArgumentError.value(upiId, 'upiId', 'Invalid UPI ID');
  }
  if (normalizedPayeeName.isEmpty) {
    throw ArgumentError.value(payeeName, 'payeeName', 'Payee name is required');
  }
  if (!amount.isFinite || amount <= 0) {
    throw ArgumentError.value(amount, 'amount', 'Amount must be positive');
  }
  if (normalizedNote.isEmpty) {
    throw ArgumentError.value(
      transactionNote,
      'transactionNote',
      'Transaction note is required',
    );
  }

  final parts = <String>[
    'pa=$normalizedUpiId',
    'pn=${encodeUpiQueryValue(normalizedPayeeName)}',
    'am=${amount.toStringAsFixed(2)}',
    'cu=INR',
    'tn=${encodeUpiQueryValue(normalizedNote)}',
  ];
  if (includeTransactionRef) {
    parts.add('tr=$normalizedRef');
  }
  return parts.join('&');
}

/// Copies the already-encoded NPCI query onto an app scheme without `+` encoding.
Uri buildUpiAppLaunchUri({
  required Uri upiPayUri,
  required UpiAppLaunchTarget target,
  bool includeTransactionRef = false,
}) {
  final params = Map<String, String>.from(upiPayUri.queryParameters);
  if (!includeTransactionRef) {
    params.remove('tr');
  }
  final query = [
    if (params['pa'] != null) 'pa=${params['pa']}',
    if (params['pn'] != null) 'pn=${encodeUpiQueryValue(params['pn']!)}',
    if (params['am'] != null) 'am=${params['am']}',
    if (params['cu'] != null) 'cu=${params['cu']}',
    if (params['tn'] != null) 'tn=${encodeUpiQueryValue(params['tn']!)}',
    if (includeTransactionRef && params['tr'] != null) 'tr=${params['tr']}',
  ].join('&');
  return Uri.parse('${target.baseUrl}?$query');
}

/// Canonical string for [launchUrl] / QR so spaces stay `%20`.
String upiLaunchString(Uri uri) {
  final params = uri.queryParameters;
  final keys = ['pa', 'pn', 'am', 'cu', 'tn', 'tr']
      .where((key) => params[key] != null && params[key]!.isNotEmpty);
  final query = keys.map((key) {
    final value = params[key]!;
    if (key == 'pn' || key == 'tn') {
      return '$key=${encodeUpiQueryValue(value)}';
    }
    return '$key=$value';
  }).join('&');
  final authority = uri.host;
  final path = uri.path;
  final base = authority.isEmpty
      ? '${uri.scheme}:$path'
      : '${uri.scheme}://$authority$path';
  return query.isEmpty ? base : '$base?$query';
}

Future<List<UpiAppOption>> getAvailableUpiApps(
  Uri upiPayUri, {
  required Future<bool> Function(Uri uri) canLaunch,
  required bool isWeb,
  required TargetPlatform platform,
}) async {
  if (!shouldOfferUpiAppShortcuts(isWeb: isWeb, platform: platform)) {
    return const [];
  }

  final available = <UpiAppOption>[];
  for (final app in configuredUpiApps) {
    for (final target in app.launchTargets) {
      final uri = buildUpiAppLaunchUri(upiPayUri: upiPayUri, target: target);
      final launchable = await _safeCanLaunch(canLaunch, uri);
      if (launchable) {
        available.add(app.withLaunchUri(uri));
        break;
      }
    }
  }
  return available;
}

Future<bool> _safeCanLaunch(
  Future<bool> Function(Uri uri) canLaunch,
  Uri uri,
) async {
  try {
    return await canLaunch(uri);
  } catch (_) {
    return false;
  }
}

bool isValidUpiId(String value) {
  final upiId = value.trim();
  return RegExp(r'^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+$').hasMatch(upiId);
}

/// NPCI `tr` values are alphanumeric. Keep a stable, unique order reference.
String sanitizeUpiTransactionRef(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (sanitized.isEmpty) return 'SBORDER';
  return sanitized.length <= 35 ? sanitized : sanitized.substring(0, 35);
}

Uri buildUpiPaymentUri({
  required String upiId,
  required String payeeName,
  required double amount,
  required String transactionNote,
  String? transactionRef,
}) {
  final query = buildUpiPayQuery(
    upiId: upiId,
    payeeName: payeeName,
    amount: amount,
    transactionNote: transactionNote,
    transactionRef: transactionRef,
  );
  return Uri.parse('upi://pay?$query');
}
