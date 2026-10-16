import 'package:flutter/foundation.dart';

import '../models/festival_banner_content.dart';

/// Local-only preview controls for the festival banner (no API/DB).
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

/// Toggle preview on the Home screen in debug builds.
class FestivalBannerPreview extends ChangeNotifier {
  FestivalBannerPreview._();
  static final FestivalBannerPreview instance = FestivalBannerPreview._();

  /// Dev chip row under the header (debug mode only).
  bool showDevControls = kDebugMode;

  FestivalBannerPreviewState previewState = kDebugMode
      ? FestivalBannerPreviewState.active
      : FestivalBannerPreviewState.hidden;

  FestivalBannerPlacement placement = FestivalBannerPlacement.belowSearch;

  /// Title, subtitle, and image — set from admin (mock) or API later.
  FestivalBannerContent content = FestivalBannerContent.placeholder;

  bool get isBannerVisible =>
      previewState == FestivalBannerPreviewState.active;

  void setContent(FestivalBannerContent value) {
    content = value;
    notifyListeners();
  }

  void setPreviewState(FestivalBannerPreviewState state) {
    previewState = state;
    notifyListeners();
  }

  void setPlacement(FestivalBannerPlacement value) {
    placement = value;
    notifyListeners();
  }

  void toggleDevControls() {
    showDevControls = !showDevControls;
    notifyListeners();
  }
}
