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

enum DeliveryReachBand { inSociety, nearby, extended }

class SellerFulfilment {
  const SellerFulfilment({
    this.mode = FulfilmentMode.buyerPickup,
    this.deliveryCharge,
    this.deliveryChargeInSociety,
    this.deliveryChargeNearby,
    this.deliveryChargeExtended,
  });

  final FulfilmentMode mode;
  final double? deliveryCharge;
  final double? deliveryChargeInSociety;
  final double? deliveryChargeNearby;
  final double? deliveryChargeExtended;

  double get inSocietyCharge => deliveryChargeInSociety ?? 0;

  double get nearbyCharge =>
      deliveryChargeNearby ?? deliveryCharge ?? 0;

  double get extendedCharge =>
      deliveryChargeExtended ?? nearbyCharge;

  double chargeForBuyer({
    bool sameSociety = true,
    DeliveryReachBand? band,
  }) {
    if (!mode.showsDeliveryCharge) return 0;
    if (sameSociety || band == DeliveryReachBand.inSociety) {
      return inSocietyCharge;
    }
    if (band == DeliveryReachBand.extended) return extendedCharge;
    return nearbyCharge;
  }

  String get subtitle {
    if (!mode.showsDeliveryCharge) return 'Buyer collects the order from you.';
    return 'In society ₹${_label(inSocietyCharge)} · Nearby ₹${_label(nearbyCharge)} · Extended ₹${_label(extendedCharge)}';
  }

  factory SellerFulfilment.fromAuthMe(Map<String, dynamic> me) {
    final nested = me['fulfilment'];
    if (nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      final nearby = _toDoubleOrNull(map['deliveryChargeNearby']) ??
          _toDoubleOrNull(map['deliveryCharge']);
      return SellerFulfilment(
        mode: parseFulfilmentMode(map['mode'] ?? me['fulfilmentMode']),
        deliveryCharge: nearby,
        deliveryChargeInSociety: _toDoubleOrNull(map['deliveryChargeInSociety']),
        deliveryChargeNearby: nearby,
        deliveryChargeExtended: _toDoubleOrNull(map['deliveryChargeExtended']) ?? nearby,
      );
    }
    final nearby = _toDoubleOrNull(me['deliveryChargeNearby']) ??
        _toDoubleOrNull(me['deliveryCharge']);
    return SellerFulfilment(
      mode: parseFulfilmentMode(me['fulfilmentMode']),
      deliveryCharge: nearby,
      deliveryChargeInSociety: _toDoubleOrNull(me['deliveryChargeInSociety']),
      deliveryChargeNearby: nearby,
      deliveryChargeExtended: _toDoubleOrNull(me['deliveryChargeExtended']) ?? nearby,
    );
  }
}

String _label(double amount) {
  return amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toString();
}

double? _toDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
