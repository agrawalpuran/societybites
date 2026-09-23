import 'package:flutter/material.dart';

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
}

class UpiAppOption {
  const UpiAppOption({
    required this.id,
    required this.displayName,
    required this.launchTargets,
    required this.icon,
    required this.accent,
    this.resolvedLaunchUri,
  });

  final String id;
  final String displayName;
  final List<UpiAppLaunchTarget> launchTargets;
  final IconData icon;
  final Color accent;
  final Uri? resolvedLaunchUri;

  UpiAppOption withLaunchUri(Uri uri) {
    return UpiAppOption(
      id: id,
      displayName: displayName,
      launchTargets: launchTargets,
      icon: icon,
      accent: accent,
      resolvedLaunchUri: uri,
    );
  }
}

/// Preferred launch targets. Query params always come from [buildUpiPaymentUri].
const configuredUpiApps = <UpiAppOption>[
  UpiAppOption(
    id: 'gpay',
    displayName: 'GPay',
    icon: Icons.account_balance_wallet_rounded,
    accent: Color(0xFF1A73E8),
    launchTargets: [
      UpiAppLaunchTarget(scheme: 'gpay', host: 'upi', path: '/pay'),
      UpiAppLaunchTarget(scheme: 'tez', host: 'upi', path: '/pay'),
    ],
  ),
  UpiAppOption(
    id: 'phonepe',
    displayName: 'PhonePe',
    icon: Icons.phone_android_rounded,
    accent: Color(0xFF5F259F),
    launchTargets: [UpiAppLaunchTarget(scheme: 'phonepe', host: 'pay')],
  ),
  UpiAppOption(
    id: 'paytm',
    displayName: 'Paytm',
    icon: Icons.payments_rounded,
    accent: Color(0xFF00BAF2),
    launchTargets: [
      UpiAppLaunchTarget(scheme: 'paytmmp', host: 'pay'),
      UpiAppLaunchTarget(scheme: 'paytm', host: 'pay'),
    ],
  ),
  UpiAppOption(
    id: 'bhim',
    displayName: 'BHIM',
    icon: Icons.currency_rupee_rounded,
    accent: Color(0xFF0E5A47),
    launchTargets: [UpiAppLaunchTarget(scheme: 'bhim', host: 'pay')],
  ),
];

/// Copies pa/pn/am/cu/tr/tn from the standard UPI pay URI onto an app scheme.
Uri buildUpiAppLaunchUri({
  required Uri upiPayUri,
  required UpiAppLaunchTarget target,
}) {
  return Uri(
    scheme: target.scheme,
    host: target.host ?? '',
    path: target.path,
    queryParameters: upiPayUri.queryParameters,
  );
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

  return Uri(
    scheme: 'upi',
    host: 'pay',
    queryParameters: {
      'pa': normalizedUpiId,
      'pn': normalizedPayeeName,
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      'tr': normalizedRef,
      'tn': normalizedNote,
    },
  );
}
