import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ThemeData> pumpTheme(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    late ThemeData theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: societyBitesTheme(),
        home: Builder(
          builder: (context) {
            theme = Theme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return theme;
  }

  testWidgets('iOS uses bundled Roboto like Android', (tester) async {
    try {
      final ios = await pumpTheme(tester, TargetPlatform.iOS);
      expect(ios.textTheme.bodyMedium?.fontFamily, kAppFontFamily);
      expect(ios.textTheme.titleLarge?.fontFamily, kAppFontFamily);
      expect(ios.primaryTextTheme.bodyMedium?.fontFamily, kAppFontFamily);

      final android = await pumpTheme(tester, TargetPlatform.android);
      expect(android.textTheme.bodyMedium?.fontFamily, kAppFontFamily);
      expect(
        ios.textTheme.bodyMedium?.fontFamily,
        android.textTheme.bodyMedium?.fontFamily,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Roboto weights stay available through the theme', (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        MaterialApp(
          theme: societyBitesTheme(),
          home: const Scaffold(
            body: Column(
              children: [
                Text('Regular', style: TextStyle(fontWeight: FontWeight.w400)),
                Text('Medium', style: TextStyle(fontWeight: FontWeight.w500)),
                Text('Semibold', style: TextStyle(fontWeight: FontWeight.w600)),
                Text('Bold', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('ExtraBold', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('Black', style: TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Regular'), findsOneWidget);
      expect(find.text('Black'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
