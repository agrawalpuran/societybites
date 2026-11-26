enum PartnerProgressKind { upcoming, current, done }

class PartnerProgressStep {
  const PartnerProgressStep({
    required this.label,
    required this.kind,
  });

  final String label;
  final PartnerProgressKind kind;
}

class PartnerDelivery {
  const PartnerDelivery({
    this.provider,
    this.state,
    this.riderName,
    this.riderPhone,
    this.trackingUrl,
    this.pickupOtp,
    this.dropOtp,
    this.quotedFare,
    this.billedFare,
    this.lspName,
    this.lastError,
  });

  final String? provider;
  final String? state;
  final String? riderName;
  final String? riderPhone;
  final String? trackingUrl;
  final String? pickupOtp;
  final String? dropOtp;
  final double? quotedFare;
  final double? billedFare;
  final String? lspName;
  final String? lastError;

  bool get isProrouting =>
      (provider ?? '').toLowerCase() == 'prorouting';

  bool get isWaitingForRider {
    switch ((state ?? '').toLowerCase()) {
      case 'quoted':
      case 'booked':
      case 'searching':
      case 'retrying':
        return true;
      default:
        return false;
    }
  }

  bool get isInFlight {
    switch ((state ?? '').toLowerCase()) {
      case 'delivered':
      case 'cancelled':
      case 'failed':
      case 'rto':
      case 'seller_fallback':
        return false;
      default:
        return true;
    }
  }

  String get stateLabel {
    switch ((state ?? '').toLowerCase()) {
      case 'quoted':
        return 'Partner delivery queued';
      case 'booked':
      case 'searching':
        return 'Finding a rider';
      case 'retrying':
        return 'Trying another rider';
      case 'assigned':
        return 'Rider assigned';
      case 'at_pickup':
        return 'Rider at pickup';
      case 'picked_up':
        return 'On the way';
      case 'at_delivery':
        return 'At delivery';
      case 'delivered':
        return 'Delivered by partner';
      case 'cancelled':
        return 'Partner delivery cancelled';
      case 'failed':
        return 'Partner booking failed';
      case 'seller_fallback':
        return 'Seller will deliver';
      case 'rto':
        return 'Returning to kitchen';
      default:
        return 'Partner delivery';
    }
  }

  static const progressLabels = [
    'Rider',
    'Pickup',
    'En route',
    'Nearby',
    'Done',
  ];

  bool get showsProgress {
    switch ((state ?? '').toLowerCase()) {
      case 'cancelled':
      case 'failed':
      case 'rto':
      case 'seller_fallback':
        return false;
      default:
        return true;
    }
  }

  int get progressIndex {
    switch ((state ?? '').toLowerCase()) {
      case 'at_pickup':
        return 1;
      case 'picked_up':
        return 2;
      case 'at_delivery':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  List<PartnerProgressStep> get progressSteps {
    if (!showsProgress) return const [];
    final current = progressIndex;
    final delivered = (state ?? '').toLowerCase() == 'delivered';
    return [
      for (var i = 0; i < progressLabels.length; i++)
        PartnerProgressStep(
          label: progressLabels[i],
          kind: delivered || i < current
              ? PartnerProgressKind.done
              : i == current
                  ? PartnerProgressKind.current
                  : PartnerProgressKind.upcoming,
        ),
    ];
  }

  factory PartnerDelivery.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const PartnerDelivery();
    }
    final json = Map<String, dynamic>.from(raw);
    return PartnerDelivery(
      provider: json['provider']?.toString(),
      state: json['state']?.toString(),
      riderName: json['riderName']?.toString(),
      riderPhone: json['riderPhone']?.toString(),
      trackingUrl: json['trackingUrl']?.toString(),
      pickupOtp: json['pickupOtp']?.toString(),
      dropOtp: json['dropOtp']?.toString(),
      quotedFare: (json['quotedFare'] as num?)?.toDouble(),
      billedFare: (json['billedFare'] as num?)?.toDouble(),
      lspName: json['lspName']?.toString(),
      lastError: json['lastError']?.toString(),
    );
  }
}
