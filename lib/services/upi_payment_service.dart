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

Uri buildUpiPaymentUri({
  required String upiId,
  required String payeeName,
  required double amount,
  required String transactionNote,
}) {
  final normalizedUpiId = upiId.trim();
  final normalizedPayeeName = payeeName.trim();
  final normalizedNote = transactionNote.trim();

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
      'tn': normalizedNote,
    },
  );
}
