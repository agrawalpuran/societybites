class IssueReport {
  const IssueReport({
    required this.id,
    required this.reference,
    required this.userRole,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    this.orderId,
    this.listingId,
    this.sellerId,
    this.adminResponse,
    this.reporterName,
  });

  final String id;
  final String reference;
  final String userRole;
  final String category;
  final String description;
  final String status;
  final DateTime createdAt;
  final String? orderId;
  final String? listingId;
  final String? sellerId;
  final String? adminResponse;
  final String? reporterName;

  static const categories = <String, String>{
    'ORDER_ISSUE': 'Order Issue',
    'PAYMENT_UPI': 'Payment / UPI',
    'FOOD_LISTING': 'Food / Listing',
    'SELLER': 'Seller',
    'BUYER': 'Buyer',
    'APP_ISSUE': 'App Issue',
    'OTHER': 'Other',
  };

  static const statuses = <String, String>{
    'OPEN': 'Open',
    'UNDER_REVIEW': 'Under Review',
    'RESOLVED': 'Resolved',
    'CLOSED': 'Closed',
  };

  String get categoryLabel => categories[category] ?? category;

  String get statusLabel => statuses[status] ?? status;

  String get roleLabel {
    if (userRole == 'seller') return 'Seller';
    if (userRole == 'super_admin') return 'Admin';
    return 'Buyer';
  }

  String get shortDescription {
    final text = description.trim();
    if (text.length <= 90) return text;
    return '${text.substring(0, 87)}...';
  }

  factory IssueReport.fromJson(Map<String, dynamic> json) {
    final reporter = json['reporter'];
    return IssueReport(
      id: json['id']?.toString() ?? '',
      reference: json['reference']?.toString() ?? '',
      userRole: json['userRole']?.toString() ?? 'buyer',
      category: json['category']?.toString() ?? 'OTHER',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'OPEN',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      orderId: _optional(json['orderId']),
      listingId: _optional(json['listingId']),
      sellerId: _optional(json['sellerId']),
      adminResponse: _optional(json['adminResponse']),
      reporterName: reporter is Map ? _optional(reporter['name']) : null,
    );
  }
}

String? _optional(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String formatIssueDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
