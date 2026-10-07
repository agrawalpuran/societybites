import 'dart:typed_data';

/// Returned from [SellerTermsScreen] when the seller accepts terms with proof.
class SellerTermsAcceptResult {
  const SellerTermsAcceptResult({
    required this.documentBytes,
    required this.documentMimeType,
  });

  final Uint8List documentBytes;
  final String documentMimeType;
}
