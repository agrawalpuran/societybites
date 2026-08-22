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
