class ServingCity {
  const ServingCity({
    required this.cityKey,
    required this.displayName,
    required this.state,
    required this.active,
  });

  final String cityKey;
  final String displayName;
  final String state;
  final bool active;

  ServingCity copyWith({bool? active}) {
    return ServingCity(
      cityKey: cityKey,
      displayName: displayName,
      state: state,
      active: active ?? this.active,
    );
  }

  factory ServingCity.fromJson(Map<String, dynamic> json) {
    return ServingCity(
      cityKey: json['cityKey']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      active: json['active'] == true,
    );
  }
}
