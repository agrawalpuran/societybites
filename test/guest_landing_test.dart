import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/config/launch_config.dart';
import 'package:societybites/models/guest_discovery.dart';
import 'package:societybites/screens/guest_landing_screen.dart';
import 'package:societybites/screens/home_screen.dart';

void _ignoreKnownLayoutNoise() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('logged-out landing shows premium guest copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GuestLandingScreen()));
    await tester.pump();

    expect(find.text('SocietyBites'), findsOneWidget);
    expect(find.textContaining('Now serving $currentServingCity'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(
      find.text('Taste what your neighbors are baking today.'),
      findsOneWidget,
    );
    expect(find.text('Explore Menus →'), findsOneWidget);
    expect(find.text('Browse as Guest'), findsOneWidget);
    expect(find.textContaining('No account required to browse.'), findsWidgets);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('CURATED CATEGORIES'), findsOneWidget);
    expect(find.textContaining('Explore All Kitchens'), findsOneWidget);
  });

  testWidgets('Browse as Guest opens existing home listings without login', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    await tester.pumpWidget(const MaterialApp(home: GuestLandingScreen()));
    await tester.pump();
    await tester.tap(find.text('Browse as Guest'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Fresh Pappardelle & Artisanal Sourdough'), findsWidgets);
  });

  test('guest discovery uses existing home categories', () {
    final categories = GuestDiscovery.curatedCategories
        .map((item) => item.homeCategory)
        .toSet();
    expect(
      categories,
      containsAll(['Lunch', 'Homemade Specials', 'Healthy', 'Desserts']),
    );
  });
}
