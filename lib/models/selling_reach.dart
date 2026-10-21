/// Legacy API levels. New sellers use [SellingReachLevel.beyondSociety] + radius km.
enum SellingReachLevel {
  mySociety,
  beyondSociety,
  nearby,
  extended,
}

SellingReachLevel parseSellingReachLevel(Object? value) {
  final raw = value?.toString().trim().toUpperCase();
  switch (raw) {
    case 'BEYOND_SOCIETY':
      return SellingReachLevel.beyondSociety;
    case 'NEARBY':
      return SellingReachLevel.nearby;
    case 'EXTENDED':
      return SellingReachLevel.extended;
    case 'MY_SOCIETY':
    default:
      return SellingReachLevel.mySociety;
  }
}

extension SellingReachLevelApi on SellingReachLevel {
  String get apiValue {
    switch (this) {
      case SellingReachLevel.mySociety:
        return 'MY_SOCIETY';
      case SellingReachLevel.beyondSociety:
        return 'BEYOND_SOCIETY';
      case SellingReachLevel.nearby:
        return 'NEARBY';
      case SellingReachLevel.extended:
        return 'EXTENDED';
    }
  }

  bool get isBeyondSociety =>
      this == SellingReachLevel.beyondSociety ||
      this == SellingReachLevel.nearby ||
      this == SellingReachLevel.extended;
}

/// Seller-facing reach choice (mode A).
class SellerReachPreference {
  const SellerReachPreference({
    required this.mySocietyOnly,
    required this.radiusKm,
  });

  final bool mySocietyOnly;
  final int radiusKm;

  static const defaultRadiusKm = 5;

  factory SellerReachPreference.fromProfile({
    required SellingReachLevel level,
    double? radiusKm,
    required SellingReach reach,
  }) {
    if (level == SellingReachLevel.mySociety) {
      return SellerReachPreference(
        mySocietyOnly: true,
        radiusKm: reach.defaultRadiusKm,
      );
    }
    final stored = radiusKm?.round();
    if (stored != null && stored > 0) {
      return SellerReachPreference(
        mySocietyOnly: false,
        radiusKm: stored.clamp(1, reach.maxRadiusKm),
      );
    }
    final legacy = level == SellingReachLevel.extended
        ? reach.extendedRadiusKm?.round()
        : reach.nearbyRadiusKm?.round();
    return SellerReachPreference(
      mySocietyOnly: false,
      radiusKm: (legacy ?? defaultRadiusKm).clamp(1, reach.maxRadiusKm),
    );
  }

  String summary(SellingReach reach) {
    if (mySocietyOnly) return 'Visible to buyers in your society';
    return 'Buyers in your society and within $radiusKm km';
  }
}

String formatReachRadiusKm(double km) {
  return km == km.roundToDouble() ? km.toInt().toString() : km.toString();
}

/// Resolved city config for the seller's society city.
class SellingReach {
  const SellingReach({
    this.cityKey,
    this.nearbyRadiusKm,
    this.extendedRadiusKm,
    this.maxSellerRadiusKm,
  });

  final String? cityKey;
  final double? nearbyRadiusKm;
  final double? extendedRadiusKm;
  final double? maxSellerRadiusKm;

  static const defaultMaxRadiusKm = 10.0;

  int get maxRadiusKm =>
      (maxSellerRadiusKm ?? defaultMaxRadiusKm).round().clamp(1, 100);

  int get defaultRadiusKm {
    final legacy = nearbyRadiusKm?.round() ?? extendedRadiusKm?.round();
    if (legacy != null && legacy >= 1) {
      return legacy.clamp(1, maxRadiusKm);
    }
    return SellerReachPreference.defaultRadiusKm.clamp(1, maxRadiusKm);
  }

  bool get beyondSocietyAvailable => cityKey != null;

  /// Buyer distance menu can offer the full city "extended" band.
  bool get extendedAvailable =>
      extendedRadiusKm != null && extendedRadiusKm! > 0;

  @Deprecated('Use SellerReachPreference.summary')
  String subtitleFor(SellingReachLevel level) {
    return SellerReachPreference.fromProfile(
      level: level,
      radiusKm: null,
      reach: this,
    ).summary(this);
  }

  factory SellingReach.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SellingReach();
    }
    return SellingReach(
      cityKey: json['cityKey'] as String?,
      nearbyRadiusKm: _toDoubleOrNull(json['nearbyRadiusKm']),
      extendedRadiusKm: _toDoubleOrNull(json['extendedRadiusKm']),
      maxSellerRadiusKm: _toDoubleOrNull(json['maxSellerRadiusKm']),
    );
  }

  static SellingReach fromAuthMe(Map<String, dynamic> me) {
    final nested = me['sellingReach'];
    if (nested is Map) {
      return SellingReach.fromJson(Map<String, dynamic>.from(nested));
    }
    return SellingReach(
      cityKey: me['cityKey'] as String?,
      nearbyRadiusKm: _toDoubleOrNull(me['nearbyRadiusKm']),
      extendedRadiusKm: _toDoubleOrNull(me['extendedRadiusKm']),
      maxSellerRadiusKm: _toDoubleOrNull(me['maxSellerRadiusKm']),
    );
  }
}

class CityReachConfig {
  const CityReachConfig({
    required this.cityKey,
    required this.displayName,
    required this.nearbyRadiusKm,
    required this.extendedRadiusKm,
    required this.maxSellerRadiusKm,
  });

  final String cityKey;
  final String displayName;
  final double nearbyRadiusKm;
  final double extendedRadiusKm;
  final double maxSellerRadiusKm;

  factory CityReachConfig.fromJson(Map<String, dynamic> json) {
    return CityReachConfig(
      cityKey: json['cityKey'] as String,
      displayName: (json['displayName'] as String?) ?? json['cityKey'] as String,
      nearbyRadiusKm: _toDoubleOrNull(json['nearbyRadiusKm']) ?? 0,
      extendedRadiusKm: _toDoubleOrNull(json['extendedRadiusKm']) ?? 0,
      maxSellerRadiusKm:
          _toDoubleOrNull(json['maxSellerRadiusKm']) ?? SellingReach.defaultMaxRadiusKm,
    );
  }
}

double? _toDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
