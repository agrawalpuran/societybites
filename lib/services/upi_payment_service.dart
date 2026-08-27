import 'package:flutter/foundation.dart';

bool shouldOfferUpiIntent({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return !isWeb && platform == TargetPlatform.android;
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
