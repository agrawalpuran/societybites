import 'package:flutter/foundation.dart';

import '../models/festival_banner_content.dart';

/// Local + server-backed home festival banner state.
enum FestivalBannerPlacement {
  /// Festive hero behind header + search (Option A).
  belowSearch,

  /// Below category chips, before Top Sellers / discovery carousels.
  belowCategories,
}

enum FestivalBannerPreviewState {
  active,
  hidden,
  loading,
  error,
}

/// Shared Home banner controller. Production loads from the API; debug
/// controls can still override on this device.
class FestivalBannerPreview extends ChangeNotifier {
  FestivalBannerPreview._();
  static final FestivalBannerPreview instance = FestivalBannerPreview._();

  /// Legacy debug chip row. Kept off so Home never shows the yellow bar.
  bool showDevControls = false;

  /// True after the admin mock/debug tools mutate local state.
  bool localOverride = false;

  FestivalBannerPreviewState previewState = FestivalBannerPreviewState.hidden;

  FestivalBannerPlacement placement = FestivalBannerPlacement.belowSearch;

  FestivalBannerContent content = FestivalBannerContent.placeholder;

  bool get isBannerVisible =>
      previewState == FestivalBannerPreviewState.active;

  static FestivalBannerPlacement placementFromApi(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'BELOW_CATEGORIES':
        return FestivalBannerPlacement.belowCategories;
      case 'BELOW_SEARCH':
      default:
        return FestivalBannerPlacement.belowSearch;
    }
  }

  static String placementToApi(FestivalBannerPlacement value) {
    switch (value) {
      case FestivalBannerPlacement.belowCategories:
        return 'BELOW_CATEGORIES';
      case FestivalBannerPlacement.belowSearch:
        return 'BELOW_SEARCH';
    }
  }

  void setContent(FestivalBannerContent value, {bool markLocal = true}) {
    content = value;
    if (markLocal) localOverride = true;
    notifyListeners();
  }

  void setPreviewState(
    FestivalBannerPreviewState state, {
    bool markLocal = true,
  }) {
    previewState = state;
    if (markLocal) localOverride = true;
    notifyListeners();
  }

  void setPlacement(FestivalBannerPlacement value, {bool markLocal = true}) {
    placement = value;
    if (markLocal) localOverride = true;
    notifyListeners();
  }

  void toggleDevControls() {
    showDevControls = !showDevControls;
    notifyListeners();
  }

  /// Apply the public active banner from the API (or clear when null).
  void applyServerBanner(Map<String, dynamic>? banner) {
    if (localOverride && kDebugMode) {
      notifyListeners();
      return;
    }
    if (banner == null) {
      content = FestivalBannerContent.placeholder;
      previewState = FestivalBannerPreviewState.hidden;
      placement = FestivalBannerPlacement.belowSearch;
      localOverride = false;
      notifyListeners();
      return;
    }
    content = FestivalBannerContent.fromJson(banner);
    placement = placementFromApi(banner['placement']?.toString());
    previewState = FestivalBannerPreviewState.active;
    localOverride = false;
    notifyListeners();
  }
}
