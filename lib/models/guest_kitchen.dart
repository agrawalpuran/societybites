class GuestKitchen {
  const GuestKitchen({
    required this.sellerId,
    required this.sellerName,
    required this.societyName,
    this.categories = const [],
    this.listings = const [],
    this.profilePhotoUrl,
  });

  final String sellerId;
  final String sellerName;
  final String societyName;
  final List<String> categories;
  final List<Map<String, dynamic>> listings;
  final String? profilePhotoUrl;

  String? get categoryLabel {
    if (categories.isEmpty) return null;
    return categories.take(3).join(' · ');
  }

  factory GuestKitchen.fromJson(Map<String, dynamic> json) {
    final seller = json['seller'] is Map
        ? Map<String, dynamic>.from(json['seller'] as Map)
        : json;
    final listingsRaw = json['listings'];
    final categoriesRaw = seller['categories'] ?? json['categories'];
    return GuestKitchen(
      sellerId: (seller['id'] ?? '').toString(),
      sellerName: (seller['name'] ?? 'Neighbor').toString(),
      societyName: (seller['societyName'] ?? '').toString(),
      categories: categoriesRaw is List
          ? categoriesRaw.map((item) => item.toString()).toList()
          : const [],
      listings: listingsRaw is List
          ? listingsRaw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const [],
      profilePhotoUrl: () {
        final raw = (seller['profilePhotoUrl'] ?? json['profilePhotoUrl'])
            ?.toString()
            .trim();
        if (raw == null || raw.isEmpty || raw == 'null') return null;
        return raw;
      }(),
    );
  }
}

class GuestKitchensResult {
  const GuestKitchensResult({
    required this.cityKey,
    required this.cityName,
    this.kitchens = const [],
  });

  final String cityKey;
  final String cityName;
  final List<GuestKitchen> kitchens;

  factory GuestKitchensResult.fromJson(Map<String, dynamic> json) {
    final raw = json['kitchens'];
    return GuestKitchensResult(
      cityKey: (json['cityKey'] ?? 'bengaluru').toString(),
      cityName: (json['cityName'] ?? 'Bengaluru').toString(),
      kitchens: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) => GuestKitchen.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
    );
  }
}
