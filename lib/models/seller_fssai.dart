class SellerFssaiRegistration {
  const SellerFssaiRegistration({
    required this.status,
    this.registrationNumber,
    this.registeredName,
    this.licenceExpiry,
    this.rejectionReason,
    this.submittedAt,
    this.reviewedAt,
    this.needsAssistance = false,
    this.hasDocument = false,
    this.requirementEnabled = false,
    this.assistanceRequested = false,
    this.canSellDespiteFssai = true,
    this.detailsDeferred = false,
  });

  final String status;
  final String? registrationNumber;
  final String? registeredName;
  final DateTime? licenceExpiry;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final bool needsAssistance;
  final bool hasDocument;
  final bool requirementEnabled;
  final bool assistanceRequested;
  final bool canSellDespiteFssai;
  final bool detailsDeferred;

  static const statusLabels = <String, String>{
    'NOT_SUBMITTED': 'Not Submitted',
    'UNDER_REVIEW': 'Under Review',
    'APPROVED': 'Approved',
    'REJECTED': 'Rejected',
  };

  String get statusLabel => statusLabels[status] ?? status;

  factory SellerFssaiRegistration.fromJson(Map<String, dynamic> json) {
    return SellerFssaiRegistration(
      status: json['status']?.toString() ?? 'NOT_SUBMITTED',
      registrationNumber: _optional(json['registrationNumber']),
      registeredName: _optional(json['registeredName']),
      licenceExpiry: _parseDate(json['licenceExpiry']),
      rejectionReason: _optional(json['rejectionReason']),
      submittedAt: DateTime.tryParse(json['submittedAt']?.toString() ?? ''),
      reviewedAt: DateTime.tryParse(json['reviewedAt']?.toString() ?? ''),
      needsAssistance: json['needsAssistance'] == true,
      hasDocument: json['hasDocument'] == true,
      requirementEnabled: json['requirementEnabled'] == true,
      assistanceRequested: json['assistanceRequested'] == true,
      canSellDespiteFssai: json['canSellDespiteFssai'] != false,
      detailsDeferred: json['detailsDeferred'] == true,
    );
  }
}

String? _optional(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _parseDate(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}
