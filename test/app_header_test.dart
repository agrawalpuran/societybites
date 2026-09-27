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

    expect(find.text('Puran Agrawal'), findsOneWidget);
    expect(find.text('Flat 3062'), findsNothing);
    expect(find.textContaining('Prestige'), findsNothing);
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
