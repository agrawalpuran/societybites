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
/// iOS GPay is probed as `tez://upi/pay` first (Indian PSP convention), then
/// `gpay://upi/pay`.
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

/// GPay in-app collect is a P2M rail. Personal VPAs fail with a fake HDFC
/// "bank limit" unless `mc` is present (empty is OK) and `tr` is unique per
/// tap. QR stays a P2P `upi://pay` string without `mc`.
Uri buildUpiAppLaunchUri({
  required Uri upiPayUri,
  required UpiAppLaunchTarget target,
  String? transactionRef,
  DateTime? now,
}) {
  final params = Map<String, String>.from(upiPayUri.queryParameters);
  final tr = sanitizeUpiTransactionRef(
    transactionRef ??
        uniqueUpiTransactionRef(
          params['tr'] ?? params['tn'] ?? 'SBORDER',
          now: now,
        ),
  );
  final query = [
    if (params['pa'] != null) 'pa=${params['pa']}',
    if (params['pn'] != null) 'pn=${encodeUpiQueryValue(params['pn']!)}',
    'mc=',
    'tr=$tr',
    if (params['tn'] != null) 'tn=${encodeUpiQueryValue(params['tn']!)}',
    if (params['am'] != null) 'am=${params['am']}',
    if (params['cu'] != null) 'cu=${params['cu']}',
    'mode=00',
  ].join('&');
  return encodedUpiLaunchUri(Uri.parse('${target.baseUrl}?$query'));
}

UpiAppLaunchTarget launchTargetFromUri(Uri uri) {
  return UpiAppLaunchTarget(
    scheme: uri.scheme,
    host: uri.host.isEmpty ? null : uri.host,
    path: uri.path,
  );
}

List<UpiAppLaunchTarget> launchTargetsFor(
  UpiAppOption app, {
  required TargetPlatform platform,
}) {
  if (app.id == 'gpay' && platform == TargetPlatform.iOS) {
    return const [
      UpiAppLaunchTarget(scheme: 'tez', host: 'upi', path: '/pay'),
      UpiAppLaunchTarget(scheme: 'gpay', host: 'upi', path: '/pay'),
    ];
  }
  return app.launchTargets;
}

/// [Uri.parse] / [Uri.toString] turn spaces into `+`. Keep NPCI `%20`.
Uri encodedUpiLaunchUri(Uri uri) {
  final launch = upiLaunchString(uri);
  final queryStart = launch.indexOf('?');
  if (queryStart < 0) return uri;
  final parsed = Uri.parse(launch);
  return Uri(
    scheme: parsed.scheme,
    host: parsed.host.isEmpty ? null : parsed.host,
    path: parsed.path,
    query: launch.substring(queryStart + 1),
  );
}

/// Canonical string for [launchUrl] / QR so spaces stay `%20`.
String upiLaunchString(Uri uri) {
  final params = uri.queryParameters;
  const keys = ['pa', 'pn', 'mc', 'tr', 'tn', 'am', 'cu', 'mode'];
  final query = <String>[];
  for (final key in keys) {
    if (!params.containsKey(key) || params[key] == null) continue;
    final value = params[key]!;
    if (value.isEmpty && key != 'mc') continue;
    if (key == 'pn' || key == 'tn') {
      query.add('$key=${encodeUpiQueryValue(value)}');
    } else {
      query.add('$key=$value');
    }
  }
  final authority = uri.host;
  final path = uri.path;
  final base = authority.isEmpty
      ? '${uri.scheme}:$path'
      : '${uri.scheme}://$authority$path';
  return query.isEmpty ? base : '$base?${query.join('&')}';
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
    for (final target in launchTargetsFor(app, platform: platform)) {
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

/// GPay rejects reused `tr` values as a fake bank-limit error.
String uniqueUpiTransactionRef(String seed, {DateTime? now}) {
  final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch.toString();
  return sanitizeUpiTransactionRef('$seed$timestamp');
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
