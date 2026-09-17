/// Seller reach level. Radius km is city-configured, not stored on the seller.
enum SellingReachLevel {
  mySociety,
  nearby,
  extended,
}

SellingReachLevel parseSellingReachLevel(Object? value) {
  final raw = value?.toString().trim().toUpperCase();
  switch (raw) {
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
      case SellingReachLevel.nearby:
        return 'NEARBY';
      case SellingReachLevel.extended:
        return 'EXTENDED';
    }
  }

  String get title {
    switch (this) {
      case SellingReachLevel.mySociety:
        return 'My Society';
      case SellingReachLevel.nearby:
        return 'Nearby';
      case SellingReachLevel.extended:
        return 'Extended';
    }
  }
}

String formatReachRadiusKm(double km) {
  return km == km.roundToDouble() ? km.toInt().toString() : km.toString();
}

/// Resolved city radii for the user's society city. Null radii mean no admin config.
class SellingReach {
  const SellingReach({
    this.cityKey,
    this.nearbyRadiusKm,
    this.extendedRadiusKm,
  });

  final String? cityKey;
  final double? nearbyRadiusKm;
  final double? extendedRadiusKm;

  bool get nearbyAvailable => nearbyRadiusKm != null;
  bool get extendedAvailable => extendedRadiusKm != null;

  String subtitleFor(SellingReachLevel level) {
    switch (level) {
      case SellingReachLevel.mySociety:
        return 'Visible to buyers in your society';
      case SellingReachLevel.nearby:
        return nearbyAvailable
            ? 'Buyers within ${formatReachRadiusKm(nearbyRadiusKm!)} km'
            : 'Nearby selling is not available in your city yet.';
      case SellingReachLevel.extended:
        return extendedAvailable
            ? 'Buyers within ${formatReachRadiusKm(extendedRadiusKm!)} km'
            : 'Nearby selling is not available in your city yet.';
    }
  }

  String optionSubtitleFor(SellingReachLevel level) {
    switch (level) {
      case SellingReachLevel.mySociety:
        return 'Buyers in your society';
      case SellingReachLevel.nearby:
        return nearbyAvailable
            ? 'Buyers within ${formatReachRadiusKm(nearbyRadiusKm!)} km'
            : 'Nearby selling is not available in your city yet.';
      case SellingReachLevel.extended:
        return extendedAvailable
            ? 'Buyers within ${formatReachRadiusKm(extendedRadiusKm!)} km'
            : 'Nearby selling is not available in your city yet.';
    }
  }

  bool isSelectable(SellingReachLevel level) {
    switch (level) {
      case SellingReachLevel.mySociety:
        return true;
      case SellingReachLevel.nearby:
        return nearbyAvailable;
      case SellingReachLevel.extended:
        return extendedAvailable;
    }
  }

  factory SellingReach.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SellingReach();
    }
    return SellingReach(
      cityKey: json['cityKey'] as String?,
      nearbyRadiusKm: _toDoubleOrNull(json['nearbyRadiusKm']),
      extendedRadiusKm: _toDoubleOrNull(json['extendedRadiusKm']),
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
    );
  }
}

class CityReachConfig {
  const CityReachConfig({
    required this.cityKey,
    required this.displayName,
    required this.nearbyRadiusKm,
    required this.extendedRadiusKm,
  });

  final String cityKey;
  final String displayName;
  final double nearbyRadiusKm;
  final double extendedRadiusKm;

  factory CityReachConfig.fromJson(Map<String, dynamic> json) {
    return CityReachConfig(
      cityKey: json['cityKey'] as String,
      displayName: (json['displayName'] as String?) ?? json['cityKey'] as String,
      nearbyRadiusKm: _toDoubleOrNull(json['nearbyRadiusKm']) ?? 0,
      extendedRadiusKm: _toDoubleOrNull(json['extendedRadiusKm']) ?? 0,
    );
  }
}

double? _toDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
