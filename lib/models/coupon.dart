class CouponQuote {
  const CouponQuote({
    required this.code,
    required this.discountAmount,
    required this.orderSubtotal,
    required this.buyerPayable,
    required this.sellerGrossAmount,
    required this.societyEatsSubsidy,
  });

  final String code;
  final double discountAmount;
  final double orderSubtotal;
  final double buyerPayable;
  final double sellerGrossAmount;
  final double societyEatsSubsidy;

  factory CouponQuote.fromJson(Map<String, dynamic> json) {
    return CouponQuote(
      code: json['code']?.toString() ?? '',
      discountAmount: _asDouble(json['discountAmount']),
      orderSubtotal: _asDouble(json['orderSubtotal']),
      buyerPayable: _asDouble(json['buyerPayable']),
      sellerGrossAmount: _asDouble(json['sellerGrossAmount']),
      societyEatsSubsidy: _asDouble(json['societyEatsSubsidy']),
    );
  }
}

String couponReasonMessage(
  String? reason, {
  double? minimumOrderValue,
  double? orderSubtotal,
}) {
  if (reason == 'MINIMUM_ORDER_NOT_MET' &&
      minimumOrderValue != null &&
      minimumOrderValue > 0) {
    final minimum = minimumOrderValue;
    final current = orderSubtotal;
    if (current != null && current < minimum) {
      final shortfall = moneyRound(minimum - current);
      return 'Minimum food order ${formatRupee(minimum)}. '
          'Add ${formatRupee(shortfall)} more to use this coupon';
    }
    return 'Minimum food order ${formatRupee(minimum)} required for this coupon';
  }
  return switch (reason) {
    'INVALID_COUPON' => 'This coupon code is not valid',
    'COUPON_EXPIRED' => 'This coupon has expired',
    'COUPON_NOT_STARTED' => 'This coupon is not active yet',
    'MINIMUM_ORDER_NOT_MET' => 'Your order does not meet the minimum for this coupon',
    'USAGE_LIMIT_REACHED' => 'This coupon has reached its usage limit',
    'BUYER_USAGE_LIMIT_REACHED' => 'You have already used this coupon',
    'NOT_ELIGIBLE' => 'This coupon is not available for your account',
    'COUPON_PAUSED' => 'This coupon is paused',
    'COUPON_EXHAUSTED' => 'This coupon is no longer available',
    'COUPON_ALREADY_APPLIED' => 'A coupon is already applied to this order',
    _ => 'This coupon could not be applied',
  };
}

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

class AdminCouponPayoutRow {
  const AdminCouponPayoutRow({
    required this.orderId,
    required this.orderNumber,
    required this.createdAt,
    this.redeemedAt,
    this.sellerId,
    this.sellerName,
    this.sellerPhone,
    required this.couponCode,
    required this.foodSubtotal,
    required this.buyerPaid,
    required this.subsidyAmount,
    required this.orderStatus,
    required this.paymentStatus,
  });

  final String orderId;
  final String orderNumber;
  final DateTime createdAt;
  final DateTime? redeemedAt;
  final String? sellerId;
  final String? sellerName;
  final String? sellerPhone;
  final String couponCode;
  final double foodSubtotal;
  final double buyerPaid;
  final double subsidyAmount;
  final String orderStatus;
  final String paymentStatus;

  factory AdminCouponPayoutRow.fromJson(Map<String, dynamic> json) {
    return AdminCouponPayoutRow(
      orderId: json['orderId'].toString(),
      orderNumber: json['orderNumber'].toString(),
      createdAt: DateTime.parse(json['createdAt'].toString()),
      redeemedAt: json['redeemedAt'] == null
          ? null
          : DateTime.tryParse(json['redeemedAt'].toString()),
      sellerId: json['sellerId']?.toString(),
      sellerName: json['sellerName']?.toString(),
      sellerPhone: json['sellerPhone']?.toString(),
      couponCode: json['couponCode']?.toString() ?? '',
      foodSubtotal: _asDouble(json['foodSubtotal']),
      buyerPaid: _asDouble(json['buyerPaid']),
      subsidyAmount: _asDouble(json['subsidyAmount']),
      orderStatus: json['orderStatus']?.toString() ?? '',
      paymentStatus: json['paymentStatus']?.toString() ?? '',
    );
  }
}

class AdminCouponPayoutSellerSummary {
  const AdminCouponPayoutSellerSummary({
    this.sellerId,
    this.sellerName,
    this.sellerPhone,
    required this.subsidyTotal,
    required this.orderCount,
  });

  final String? sellerId;
  final String? sellerName;
  final String? sellerPhone;
  final double subsidyTotal;
  final int orderCount;

  factory AdminCouponPayoutSellerSummary.fromJson(Map<String, dynamic> json) {
    return AdminCouponPayoutSellerSummary(
      sellerId: json['sellerId']?.toString(),
      sellerName: json['sellerName']?.toString(),
      sellerPhone: json['sellerPhone']?.toString(),
      subsidyTotal: _asDouble(json['subsidyTotal']),
      orderCount: _asInt(json['orderCount']) ?? 0,
    );
  }
}

class AdminCouponSellerPayoutReport {
  const AdminCouponSellerPayoutReport({
    required this.totalSubsidy,
    required this.rowCount,
    required this.rows,
    required this.bySeller,
  });

  final double totalSubsidy;
  final int rowCount;
  final List<AdminCouponPayoutRow> rows;
  final List<AdminCouponPayoutSellerSummary> bySeller;

  factory AdminCouponSellerPayoutReport.fromJson(Map<String, dynamic> json) {
    return AdminCouponSellerPayoutReport(
      totalSubsidy: _asDouble(json['totalSubsidy']),
      rowCount: _asInt(json['rowCount']) ?? 0,
      rows: (json['rows'] as List? ?? const [])
          .map(
            (row) => AdminCouponPayoutRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
      bySeller: (json['bySeller'] as List? ?? const [])
          .map(
            (row) => AdminCouponPayoutSellerSummary.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
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

double moneyRound(double value) {
  return (value * 100).round() / 100;
}

double? optionalCouponAmount(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
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
