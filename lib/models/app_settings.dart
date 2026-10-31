/// Public platform settings from GET /settings.
class AppSettings {
  const AppSettings({
    this.platformFee = 0,
    this.minIosBuild = 0,
    this.minAndroidBuild = 0,
    this.iosUpdateUrl = '',
    this.androidUpdateUrl = '',
    this.servingCities = const ['Bengaluru'],
    this.servingCityLabel = 'Bengaluru',
  });

  final double platformFee;
  final int minIosBuild;
  final int minAndroidBuild;
  final String iosUpdateUrl;
  final String androidUpdateUrl;
  final List<String> servingCities;
  final String servingCityLabel;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    int asBuild(Object? raw) {
      final parsed = raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '');
      if (parsed == null || parsed < 0) return 0;
      return parsed;
    }

    final cities = _servingCities(json['servingCities']);
    final label = json['servingCityLabel']?.toString().trim() ?? '';

    return AppSettings(
      platformFee: (json['platformFee'] as num?)?.toDouble() ?? 0,
      minIosBuild: asBuild(json['minIosBuild']),
      minAndroidBuild: asBuild(json['minAndroidBuild']),
      iosUpdateUrl: json['iosUpdateUrl']?.toString().trim() ?? '',
      androidUpdateUrl: json['androidUpdateUrl']?.toString().trim() ?? '',
      servingCities: cities,
      servingCityLabel: label.isEmpty ? cities.join(', ') : label,
    );
  }

  static List<String> _servingCities(Object? raw) {
    if (raw is List) {
      final names = raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (names.isNotEmpty) return names;
    }
    return const ['Bengaluru'];
  }
}
