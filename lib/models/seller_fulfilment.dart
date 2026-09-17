enum FulfilmentMode {
  buyerPickup,
  sellerDelivery,
  both,
}

FulfilmentMode parseFulfilmentMode(Object? value) {
  switch (value?.toString().trim().toUpperCase()) {
    case 'SELLER_DELIVERY':
      return FulfilmentMode.sellerDelivery;
    case 'BOTH':
      return FulfilmentMode.both;
    case 'BUYER_PICKUP':
    default:
      return FulfilmentMode.buyerPickup;
  }
}

extension FulfilmentModeApi on FulfilmentMode {
  String get apiValue {
    switch (this) {
      case FulfilmentMode.buyerPickup:
        return 'BUYER_PICKUP';
      case FulfilmentMode.sellerDelivery:
        return 'SELLER_DELIVERY';
      case FulfilmentMode.both:
        return 'BOTH';
    }
  }

  String get title {
    switch (this) {
      case FulfilmentMode.buyerPickup:
        return 'Buyer Pickup';
      case FulfilmentMode.sellerDelivery:
        return 'Seller Delivery';
      case FulfilmentMode.both:
        return 'Pickup + Seller Delivery';
    }
  }

  String get optionTitle {
    switch (this) {
      case FulfilmentMode.buyerPickup:
        return 'Buyer Pickup';
      case FulfilmentMode.sellerDelivery:
        return 'Seller Delivery';
      case FulfilmentMode.both:
        return 'Both';
    }
  }

  String get optionSubtitle {
    switch (this) {
      case FulfilmentMode.buyerPickup:
        return 'Buyer collects the order from you.';
      case FulfilmentMode.sellerDelivery:
        return 'You arrange delivery to the buyer.';
      case FulfilmentMode.both:
        return 'Buyer can collect or you can deliver.';
    }
  }

  bool get showsDeliveryCharge =>
      this == FulfilmentMode.sellerDelivery || this == FulfilmentMode.both;
}

class SellerFulfilment {
  const SellerFulfilment({
    this.mode = FulfilmentMode.buyerPickup,
    this.deliveryCharge,
  });

  final FulfilmentMode mode;
  final double? deliveryCharge;

  String get subtitle {
    if (!mode.showsDeliveryCharge) return 'Buyer collects the order from you.';
    final amount = deliveryCharge ?? 0;
    final label = amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toString();
    return '₹$label delivery charge';
  }

  factory SellerFulfilment.fromAuthMe(Map<String, dynamic> me) {
    final nested = me['fulfilment'];
    if (nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      return SellerFulfilment(
        mode: parseFulfilmentMode(map['mode'] ?? me['fulfilmentMode']),
        deliveryCharge: _toDoubleOrNull(map['deliveryCharge']),
      );
    }
    return SellerFulfilment(
      mode: parseFulfilmentMode(me['fulfilmentMode']),
      deliveryCharge: _toDoubleOrNull(me['deliveryCharge']),
    );
  }
}

double? _toDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
