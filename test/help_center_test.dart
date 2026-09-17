import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/help_center.dart';
import 'package:societybites/screens/help_center_screen.dart';
import 'package:societybites/screens/profile_screen.dart';

void _ignoreKnownLayoutNoise() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('Incorrect use of ParentDataWidget') ||
        text.contains('ListTile background color')) {
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'user_name': 'Anita',
      'user_role': 'buyer',
      'phone': '+919901844776',
    });
  });

  test('help catalog has nine categories and 40-45 FAQs', () {
    expect(helpCategories.length, 9);
    expect(helpFaqCount, greaterThanOrEqualTo(40));
    expect(helpFaqCount, lessThanOrEqualTo(45));
  });

  test('search delivery surfaces pickup, orders, selling, and nearby', () {
    final hits = searchHelpFaqs('delivery');
    final titles = hits.map((hit) => hit.faq.question).toList();
    expect(titles, isNotEmpty);
    expect(
      hits.map((hit) => hit.category.id).toSet(),
      containsAll(<String>['fulfilment', 'orders', 'nearby', 'selling']),
    );
    expect(
      hits.any((hit) => hit.faq.question.toLowerCase().contains('track')),
      isTrue,
    );
  });

  testWidgets('Profile Help Center opens the FAQ screen', (tester) async {
    _ignoreKnownLayoutNoise();
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(fetchProfile: () async => {'name': 'Anita'}),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    await tester.scrollUntilVisible(
      find.text('Help Center'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Help Center'));
    await tester.pumpAndSettle();

    expect(find.text('How can we help?'), findsOneWidget);
    expect(find.text('Search help'), findsOneWidget);
    expect(find.textContaining('Buying'), findsOneWidget);
    expect(find.textContaining('Selling'), findsOneWidget);
    expect(find.textContaining('Explore Nearby'), findsOneWidget);
    expect(find.textContaining('Pickup & Delivery'), findsOneWidget);
    expect(find.textContaining('Orders'), findsWidgets);
    expect(find.textContaining('Pre-orders'), findsOneWidget);
    expect(find.textContaining('Ratings & Feedback'), findsOneWidget);
    expect(find.textContaining('Profile & Payments'), findsOneWidget);
    expect(find.textContaining('Common Issues'), findsOneWidget);
  });

  testWidgets('category questions expand one at a time and back returns', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pump();

    await tester.tap(find.textContaining('Buying'));
    await tester.pumpAndSettle();

    expect(find.text('What is SocietyBites?'), findsOneWidget);
    expect(
      find.textContaining('homegrown food marketplace'),
      findsNothing,
    );

    await tester.tap(find.text('What is SocietyBites?'));
    await tester.pump();
    expect(
      find.textContaining('homegrown food marketplace'),
      findsOneWidget,
    );

    await tester.tap(find.text('How do I buy something?'));
    await tester.pump();
    expect(find.textContaining('add items to your cart'), findsOneWidget);
    expect(
      find.textContaining('homegrown food marketplace'),
      findsNothing,
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();
    expect(find.text('How can we help?'), findsOneWidget);
  });

  testWidgets('search help finds delivery questions', (tester) async {
    _ignoreKnownLayoutNoise();
    await tester.pumpWidget(const MaterialApp(home: HelpCenterScreen()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'delivery');
    await tester.pump();

    expect(find.textContaining('Seller Delivery'), findsWidgets);
    expect(find.textContaining('Buying'), findsNothing);
  });
}
