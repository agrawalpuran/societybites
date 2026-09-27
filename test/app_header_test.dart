import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/services/cart_controller.dart';
import 'package:societybites/widgets/app_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(CartController.instance.clear);

  testWidgets('header shows the name without flat or society', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'user_name': 'Puran Agrawal',
      'flat_number': '3062',
      'society_name': 'Prestige Notting Hill',
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppHeader())),
    );
    await tester.pumpAndSettle();

    expect(find.text(kAppDisplayName), findsOneWidget);
    expect(find.text('Puran Agrawal'), findsOneWidget);
    expect(find.text('Flat 3062'), findsNothing);
    expect(find.textContaining('Prestige'), findsNothing);
  });

  testWidgets('brand name stays on one line on a narrow phone', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'user_name': 'Puran Agrawal',
    });
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = '${details.exception}\n${details.summary}';
      if (text.contains('A RenderFlex overflowed')) {
        overflows.add(text.split('\n').first);
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppHeader())),
    );
    await tester.pumpAndSettle();

    final brand = tester.widget<Text>(find.text(kAppDisplayName));
    expect(brand.maxLines, 1);
    expect(brand.softWrap, isFalse);
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });

  testWidgets('header can hide cart and user on product details', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'user_name': 'Puran Agrawal',
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppHeader(showCart: false, showUser: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Puran Agrawal'), findsNothing);
    expect(find.text('Cart'), findsNothing);
    expect(find.byKey(const Key('home-cart-button')), findsNothing);
  });

  testWidgets('header hides cart until an item is added', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'user_name': 'Puran Agrawal',
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppHeader())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cart'), findsNothing);
    expect(find.byKey(const Key('home-cart-button')), findsNothing);
  });
}
