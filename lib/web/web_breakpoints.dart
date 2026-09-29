import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Web marketplace layout. Android and iOS never enter this path.
const webCompactMinWidth = 768.0;
const webDesktopMinWidth = 1200.0;
const webFrameMaxWidth = 1180.0;

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

int webFoodColumnCount(double width) {
  if (width >= webDesktopMinWidth) return 4;
  if (width >= 980) return 3;
  return 2;
}

int webSellerColumnCount(double width) => width >= webDesktopMinWidth ? 4 : 2;

double webPagePadding(double width) => webIsDesktopWidth(width) ? 28 : 20;
