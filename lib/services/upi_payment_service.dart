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

/// iOS GPay/PhonePe collect (`://upi/pay`) is a merchant rail. Personal
/// neighbour VPAs fail there with HDFC's fake bank-limit screen. Open the
/// UPI app instead and let the buyer paste the copied VPA.
bool shouldHandoffUpiCollect({required TargetPlatform platform}) {
  return platform == TargetPlatform.iOS;
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
    if (authority.isEmpty) {
      return path.isEmpty ? '$scheme://' : '$scheme:$path';
    }
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

/// Preferred Android collect targets. Query always comes from
/// [buildUpiAppLaunchUri]. iOS never uses these hosts — see
/// [shouldHandoffUpiCollect].
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

/// App shortcuts must look like a P2P send-to-VPA. `mc`, `tr`, `tn`, and
/// `mode` make GPay treat a neighbour's personal VPA as a merchant collect.
/// HDFC then rejects Pay with a fake "bank limit" even though the same
/// amount succeeds when the UPI ID is pasted in GPay. QR stays the full
/// NPCI `upi://pay` string.
Uri buildUpiAppLaunchUri({
  required Uri upiPayUri,
  required UpiAppLaunchTarget target,
}) {
  final params = Map<String, String>.from(upiPayUri.queryParameters);
  final query = [
    if (params['pa'] != null) 'pa=${params['pa']}',
    if (params['pn'] != null) 'pn=${encodeUpiQueryValue(params['pn']!)}',
    if (params['am'] != null) 'am=${params['am']}',
    if (params['cu'] != null) 'cu=${params['cu']}',
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
  if (shouldHandoffUpiCollect(platform: platform)) {
    if (app.id == 'gpay') {
      return const [
        UpiAppLaunchTarget(scheme: 'tez'),
        UpiAppLaunchTarget(scheme: 'gpay'),
      ];
    }
    final seen = <String>{};
    return [
      for (final target in app.launchTargets)
        if (seen.add(target.scheme)) UpiAppLaunchTarget(scheme: target.scheme),
    ];
  }
  return app.launchTargets;
}

Uri buildUpiAppOpenUri(UpiAppLaunchTarget target) {
  return Uri.parse(target.baseUrl);
}

String upiHandoffCopyHint({
  required String appName,
  required String amount,
}) {
  return 'UPI ID copied. Pay ₹$amount in $appName to the copied ID.';
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
      ? (path.isEmpty ? '${uri.scheme}://' : '${uri.scheme}:$path')
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
      final uri = shouldHandoffUpiCollect(platform: platform)
          ? buildUpiAppOpenUri(target)
          : buildUpiAppLaunchUri(upiPayUri: upiPayUri, target: target);
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
