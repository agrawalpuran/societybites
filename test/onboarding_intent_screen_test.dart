import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/onboarding_intent_screen.dart';
import 'package:societybites/services/session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('order and sell choices are visible with footnote', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingIntentScreen()),
    );
    await tester.pump();

    expect(find.text('What brings you here?'), findsOneWidget);
    expect(find.text('Order food'), findsOneWidget);
    expect(find.text('Sell food'), findsOneWidget);
    expect(
      find.textContaining('Sellers can still order'),
      findsOneWidget,
    );
    expect(find.text('Use a different number'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing sell stores seller onboarding intent', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingIntentScreen()),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding-intent-sell')));
    await tester.pump();

    expect(
      await SessionService.getOnboardingIntent(),
      SessionService.onboardingIntentSeller,
    );
  });
}
