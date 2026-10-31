import '../config/launch_config.dart';
import 'api_service.dart';

/// Public "Now serving" line. Screens keep [currentServingCity] until this resolves.
class ServingCityLabel {
  static Future<String> Function() load = _loadFromSettings;

  static Future<String> _loadFromSettings() async {
    final settings = await ApiService.getAppSettings(forceRefresh: true);
    final label = settings.servingCityLabel.trim();
    if (label.isEmpty) return currentServingCity;
    return label;
  }
}
