class StorefrontBranding {
  const StorefrontBranding({
    required this.accentColor,
    this.bannerUrl,
    this.tagline,
  });

  final String accentColor;
  final String? bannerUrl;
  final String? tagline;

  factory StorefrontBranding.fromJson(Map<String, dynamic> json) {
    return StorefrontBranding(
      accentColor: (json['accentColor'] ?? '#0E5A47').toString(),
      bannerUrl: json['bannerUrl']?.toString(),
      tagline: json['tagline']?.toString(),
    );
  }
}

class StorefrontKitchenPayload {
  const StorefrontKitchenPayload({
    required this.slug,
    required this.branding,
    required this.seller,
    this.listings = const [],
  });

  final String slug;
  final StorefrontBranding branding;
  final Map<String, dynamic> seller;
  final List<Map<String, dynamic>> listings;

  String get sellerId => seller['id']?.toString() ?? '';
  String get sellerName => seller['name']?.toString() ?? 'Kitchen';
  String get societyName => seller['societyName']?.toString() ?? '';

  factory StorefrontKitchenPayload.fromJson(Map<String, dynamic> json) {
    final sellerRaw = json['seller'];
    final listingsRaw = json['listings'];
    return StorefrontKitchenPayload(
      slug: json['slug']?.toString() ?? '',
      branding: StorefrontBranding.fromJson(
        json['branding'] is Map
            ? Map<String, dynamic>.from(json['branding'] as Map)
            : const {},
      ),
      seller: sellerRaw is Map
          ? Map<String, dynamic>.from(sellerRaw)
          : const {},
      listings: listingsRaw is List
          ? listingsRaw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : const [],
    );
  }
}
