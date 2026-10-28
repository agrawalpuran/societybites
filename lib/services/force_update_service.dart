import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_settings.dart';
import 'api_service.dart';

class ForceUpdateRequirement {
  const ForceUpdateRequirement({
    required this.currentBuild,
    required this.minBuild,
    required this.updateUrl,
  });

  final int currentBuild;
  final int minBuild;
  final String updateUrl;
}

/// Hard gate for native apps. Web always skips.
class ForceUpdateService {
  ForceUpdateService._();

  static Future<ForceUpdateRequirement?> check() async {
    if (kIsWeb) return null;

    try {
      final settings = await ApiService.getAppSettings();
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;
      final minBuild = _minBuildForPlatform(settings);
      if (minBuild <= 0 || currentBuild >= minBuild) return null;

      return ForceUpdateRequirement(
        currentBuild: currentBuild,
        minBuild: minBuild,
        updateUrl: _updateUrlForPlatform(settings),
      );
    } catch (error, stack) {
      // Fail open: do not brick the app if settings are unreachable.
      debugPrint('[force-update] check failed: $error\n$stack');
      return null;
    }
  }

  static int _minBuildForPlatform(AppSettings settings) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return settings.minIosBuild;
      case TargetPlatform.android:
        return settings.minAndroidBuild;
      default:
        return 0;
    }
  }

  static String _updateUrlForPlatform(AppSettings settings) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return settings.iosUpdateUrl;
      case TargetPlatform.android:
        return settings.androidUpdateUrl;
      default:
        return '';
    }
  }
}
