import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StorefrontThemeScope extends StatelessWidget {
  const StorefrontThemeScope({
    super.key,
    required this.accentHex,
    required this.child,
  });

  final String accentHex;
  final Widget child;

  Color? _parseHex(String raw) {
    final text = raw.trim();
    final match = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(text);
    if (match == null) return null;
    final hex = match.group(1)!;
    final value = int.parse(hex, radix: 16);
    return Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _parseHex(accentHex) ?? const Color(0xFF0E5A47);
    final base = societyBitesTheme();
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: accent,
          secondary: accent,
        ),
        floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
          backgroundColor: accent,
        ),
      ),
      child: child,
    );
  }
}
