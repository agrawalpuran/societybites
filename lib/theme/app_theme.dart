import 'package:flutter/material.dart';

const kAppFontFamily = 'Roboto';

/// Material/Roboto typography on every platform (including iOS).
ThemeData societyBitesTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: kAppFontFamily,
    typography: Typography.material2021(platform: TargetPlatform.android),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: kAppFontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kAppFontFamily),
  );
}
