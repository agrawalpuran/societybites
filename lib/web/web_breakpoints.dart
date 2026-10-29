import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Web marketplace layout. Android and iOS never enter this path.
const webCompactMinWidth = 768.0;
const webDesktopMinWidth = 1200.0;
const webFrameMaxWidth = 1180.0;

/// Seller tools (My Kitchen, My Listings, add listing form) — avoids stretched mobile layout on desktop.
const webSellerContentMaxWidth = 840.0;

const webPageBackground = Color(0xFFF3F6F1);
const webInk = Color(0xFF172421);
const webMuted = Color(0xFF6B7874);
const webGreen = Color(0xFF0E5A47);
const webGreenDark = Color(0xFF0A4638);
const webLine = Color(0xFFE3E8E4);
const webHeroWash = Color(0xFFE5F2EA);

bool webMarketplaceLayoutEnabled({
  required bool isWeb,
  required double width,
}) {
  return isWeb && width >= webCompactMinWidth;
}

bool useWebMarketplaceLayout(BuildContext context) {
  return webMarketplaceLayoutEnabled(
    isWeb: kIsWeb,
    width: MediaQuery.sizeOf(context).width,
  );
}

bool webIsDesktopWidth(double width) => width >= webDesktopMinWidth;

/// Column counts use the marketplace content width (≤ [webFrameMaxWidth]),
/// not the browser viewport — so thresholds sit below the frame max.
int webFoodColumnCount(double width) {
  if (width >= 1040) return 5;
  if (width >= 860) return 4;
  if (width >= 700) return 3;
  return 2;
}

int webSellerColumnCount(double width) {
  if (width >= 1040) return 4;
  if (width >= 760) return 3;
  return 2;
}

/// Shared grid gap — tight enough for fair density, not cramped.
const webGridGap = 12.0;

double webPagePadding(double width) => webIsDesktopWidth(width) ? 28 : 20;
