class AdminCoupon {
  const AdminCoupon({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.maximumDiscount,
    required this.minimumOrderValue,
    required this.validFrom,
    required this.validUntil,
    this.totalUsageLimit,
    this.usagePerBuyerLimit,
    this.usageFrequency,
    this.campaignBudget,
    required this.audienceType,
    required this.status,
    required this.fundedBy,
    required this.totalUsage,
    required this.appliedCount,
    required this.reversedCount,
    required this.amountUsed,
    this.remainingBudget,
    this.eligibleUserIds = const [],
  });

  final String id;
  final String code;
  final String name;
  final String? description;
  final String discountType;
  final double discountValue;
  final double? maximumDiscount;
  final double minimumOrderValue;
  final DateTime validFrom;
  final DateTime validUntil;
  final int? totalUsageLimit;
  final int? usagePerBuyerLimit;
  final String? usageFrequency;
  final double? campaignBudget;
  final String audienceType;
  final String status;
  final String fundedBy;
  final int totalUsage;
  final int appliedCount;
  final int reversedCount;
  final double amountUsed;
  final double? remainingBudget;
  final List<String> eligibleUserIds;

  bool get hasRedemptions =>
      totalUsage > 0 || appliedCount > 0 || reversedCount > 0;

  String get discountLabel {
    if (discountType == 'PERCENTAGE') {
      final cap = maximumDiscount == null ? '' : ' up to ${formatRupee(maximumDiscount!)}';
      return '${_trimNumber(discountValue)}%$cap off';
    }
    return '${formatRupee(discountValue)} off';
  }

  String get statusLabel => switch (status) {
        'DRAFT' => 'Draft',
        'ACTIVE' => 'Active',
        'PAUSED' => 'Paused',
        'EXPIRED' => 'Expired',
        'EXHAUSTED' => 'Exhausted',
        _ => status,
      };

  factory AdminCoupon.fromJson(Map<String, dynamic> json) {
    return AdminCoupon(
      id: json['id'].toString(),
      code: json['code'].toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      discountType: json['discountType']?.toString() ?? 'FIXED',
      discountValue: _asDouble(json['discountValue']),
      maximumDiscount: json['maximumDiscount'] == null
          ? null
          : _asDouble(json['maximumDiscount']),
      minimumOrderValue: _asDouble(json['minimumOrderValue']),
      validFrom: DateTime.parse(json['validFrom'].toString()),
      validUntil: DateTime.parse(json['validUntil'].toString()),
      totalUsageLimit: _asInt(json['totalUsageLimit']),
      usagePerBuyerLimit: _asInt(json['usagePerBuyerLimit']),
      usageFrequency: json['usageFrequency']?.toString(),
      campaignBudget: json['campaignBudget'] == null
          ? null
          : _asDouble(json['campaignBudget']),
      audienceType: json['audienceType']?.toString() ?? 'ALL',
      status: json['status']?.toString() ?? 'DRAFT',
      fundedBy: json['fundedBy']?.toString() ?? 'SOCIETYEATS',
      totalUsage: _asInt(json['totalUsage']) ?? 0,
      appliedCount: _asInt(json['appliedCount']) ?? 0,
      reversedCount: _asInt(json['reversedCount']) ?? 0,
      amountUsed: _asDouble(json['amountUsed']),
      remainingBudget: json['remainingBudget'] == null
          ? null
          : _asDouble(json['remainingBudget']),
      eligibleUserIds: (json['eligibleUserIds'] as List?)
              ?.map((id) => id.toString())
              .toList() ??
          const [],
    );
  }
}

String formatRupee(num value) {
  final rounded = (value * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) return '₹${rounded.toInt()}';
  return '₹${rounded.toStringAsFixed(2)}';
}

String formatCouponDate(DateTime value) {
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

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

String _trimNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
