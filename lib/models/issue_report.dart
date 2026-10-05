class IssueMessage {
  const IssueMessage({
    required this.id,
    required this.authorRole,
    required this.body,
    required this.createdAt,
    this.imageUrl,
  });

  final String id;
  final String authorRole;
  final String body;
  final DateTime createdAt;
  final String? imageUrl;

  bool get isSocietyEats => authorRole == 'SOCIETYEATS';

  factory IssueMessage.fromJson(Map<String, dynamic> json) {
    return IssueMessage(
      id: json['id']?.toString() ?? '',
      authorRole: json['authorRole']?.toString() ?? 'USER',
      body: json['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      imageUrl: _optional(json['imageUrl']),
    );
  }
}

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
    this.imageUrl,
    this.reporterName,
    this.messages = const [],
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
  final String? imageUrl;
  final String? reporterName;
  final List<IssueMessage> messages;

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
      imageUrl: _optional(json['imageUrl']),
      reporterName: reporter is Map ? _optional(reporter['name']) : null,
      messages: json['messages'] is List
          ? (json['messages'] as List)
              .whereType<Map>()
              .map((row) => IssueMessage.fromJson(Map<String, dynamic>.from(row)))
              .toList()
          : const [],
    );
  }
}

String? _optional(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String formatIssueDate(DateTime value) {
  final ist = _asIst(value);
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
  return '${ist.day} ${months[ist.month - 1]} ${ist.year}';
}

String formatIssueDateTimeIst(DateTime value) {
  final ist = _asIst(value);
  final hour = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
  final minute = ist.minute.toString().padLeft(2, '0');
  final suffix = ist.hour >= 12 ? 'pm' : 'am';
  return '${formatIssueDate(value)}, $hour:$minute $suffix IST';
}

DateTime _asIst(DateTime value) {
  return value.toUtc().add(const Duration(hours: 5, minutes: 30));
}
