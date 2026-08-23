import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('all four labels stay visible on every selected tab', (
    tester,
  ) async {
    for (var selected = 0; selected < 4; selected++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(
              selectedIndex: selected,
              onTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shopping_bag_rounded), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    }
  });

  testWidgets('nav stays compact so the scaffold body keeps its height', (
    tester,
  ) async {
    const bodyKey = ValueKey('body');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const ColoredBox(
            key: bodyKey,
            color: Colors.white,
            child: SizedBox.expand(),
          ),
          bottomNavigationBar: AppBottomNav(selectedIndex: 0, onTap: (_) {}),
        ),
      ),
    );

    final screenHeight =
        (tester.view.physicalSize / tester.view.devicePixelRatio).height;
    final navRect = tester.getRect(find.byType(AppBottomNav));

    expect(navRect.height, lessThan(80));
    expect(navRect.bottom, screenHeight);
    expect(
      tester.getSize(find.byKey(bodyKey)).height,
      screenHeight - navRect.height,
    );
  });

  testWidgets('tapping items still reports the same tab indices', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(selectedIndex: 0, onTap: taps.add),
        ),
      ),
    );

    await tester.tap(find.text('Orders'));
    await tester.tap(find.text('Dashboard'));
    await tester.tap(find.text('Profile'));
    await tester.tap(find.text('Home'));

    expect(taps, [1, 2, 3, 0]);
  });
}
