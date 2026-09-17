import 'data.dart';
import 'seller_fulfilment.dart';

class NearbyDiscoveryResult {
  const NearbyDiscoveryResult({
    required this.available,
    this.reason,
    this.buyerSocietyName,
    this.appliedRadiusKm,
    this.sellers = const [],
  });

  final bool available;
  final String? reason;
  final String? buyerSocietyName;
  final double? appliedRadiusKm;
  final List<NearbySellerCard> sellers;

  factory NearbyDiscoveryResult.fromJson(Map<String, dynamic> json) {
    final rawSellers = json['sellers'];
    return NearbyDiscoveryResult(
      available: json['available'] != false,
      reason: json['reason']?.toString(),
      buyerSocietyName: json['buyerSocietyName']?.toString(),
      appliedRadiusKm: _toDouble(json['appliedRadiusKm']),
      sellers: rawSellers is List
          ? rawSellers
                .whereType<Map>()
                .map(
                  (item) => NearbySellerCard.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class NearbySellerCard {
  const NearbySellerCard({
    required this.sellerId,
    required this.sellerName,
    required this.societyName,
    this.distanceKm,
    required this.fulfilment,
    this.listings = const [],
  });

  final String sellerId;
  final String sellerName;
  final String societyName;
  final double? distanceKm;
  final SellerFulfilment fulfilment;
  final List<FoodItem> listings;

  String get distanceLabel {
    final km = distanceKm;
    if (km == null) return '';
    if (km <= 0) return 'In your society';
    final text = km == km.roundToDouble()
        ? km.toInt().toString()
        : km.toStringAsFixed(1);
    return '$text km away';
  }

  bool get offersPickup =>
      fulfilment.mode == FulfilmentMode.buyerPickup ||
      fulfilment.mode == FulfilmentMode.both;

  bool get offersDelivery =>
      fulfilment.mode == FulfilmentMode.sellerDelivery ||
      fulfilment.mode == FulfilmentMode.both;

  String? get deliveryChargeLabel {
    if (!offersDelivery) return null;
    final amount = fulfilment.deliveryCharge ?? 0;
    if (amount <= 0) return 'Free delivery';
    final text = amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toString();
    return 'Delivery ₹$text';
  }

  Seller toSeller() {
    return sellerFromListing(
      listings.isNotEmpty
          ? listings.first
          : FoodItem.fromJson({
              'id': 'nearby-$sellerId',
              'name': sellerName,
              'sellerId': sellerId,
              'sellerName': sellerName,
              'price': 0,
            }),
    );
  }

  factory NearbySellerCard.fromJson(Map<String, dynamic> json) {
    final seller = json['seller'] is Map
        ? Map<String, dynamic>.from(json['seller'] as Map)
        : <String, dynamic>{};
    final listingsRaw = json['listings'];
    return NearbySellerCard(
      sellerId: (seller['id'] ?? json['id'] ?? '').toString(),
      sellerName: (seller['name'] ?? 'Neighbor').toString(),
      societyName: (seller['societyName'] ?? '').toString(),
      distanceKm: _toDouble(seller['distanceKm'] ?? json['distanceKm']),
      fulfilment: SellerFulfilment.fromAuthMe({
        'fulfilment': json['fulfilment'],
        'fulfilmentMode': json['fulfilmentMode'],
        'deliveryCharge': json['deliveryCharge'],
      }),
      listings: listingsRaw is List
          ? listingsRaw
                .whereType<Map>()
                .map((item) => FoodItem.fromJson(Map<String, dynamic>.from(item)))
                .toList()
          : const [],
    );
  }
}

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
