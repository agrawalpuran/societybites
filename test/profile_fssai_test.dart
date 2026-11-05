import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/profile_screen.dart';

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('Incorrect use of ParentDataWidget') ||
        text.contains('ListTile background color')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seller profile shows FSSAI details for existing sellers', (
    tester,
  ) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'seller-1',
            'name': 'Anita',
            'role': 'seller',
            'sellingReachLevel': 'MY_SOCIETY',
            'sellingReach': {
              'cityKey': 'bengaluru',
              'nearbyRadiusKm': 5,
              'extendedRadiusKm': 10,
            },
            'fulfilmentMode': 'BUYER_PICKUP',
            'fssai': {'number': null},
            'society': {'name': 'Prestige Notting Hill'},
            'flat': {'flatNumber': '3062'},
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('Seller Settings'));
    await tester.tap(find.text('Seller Settings'));
    await tester.pumpAndSettle();

    expect(find.textContaining('FSSAI details'), findsOneWidget);
    expect(find.textContaining('Required'), findsWidgets);
  });

  testWidgets('saved FSSAI details are shown on seller profile', (tester) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'seller-1',
            'name': 'Anita',
            'role': 'seller',
            'sellingReachLevel': 'MY_SOCIETY',
            'sellingReach': {
              'cityKey': 'bengaluru',
              'nearbyRadiusKm': 5,
              'extendedRadiusKm': 10,
            },
            'fulfilmentMode': 'BUYER_PICKUP',
            'fssai': {
              'number': '12345678901234',
              'registeredName': 'Agrawal Kitchen',
              'expiry': '2027-12-31',
            },
            'society': {'name': 'Prestige Notting Hill'},
            'flat': {'flatNumber': '3062'},
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.text('Seller Settings'));
    await tester.tap(find.text('Seller Settings'));
    await tester.pumpAndSettle();

    expect(find.textContaining('12345678901234'), findsWidgets);
    expect(find.textContaining('FSSAI details'), findsOneWidget);
  });

  testWidgets('buyer profile does not show FSSAI details', (tester) async {
    _ignoreOverflow();
    SharedPreferences.setMockInitialValues({
      'user_id': 'buyer-1',
      'user_role': 'buyer',
    });
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'buyer-1',
            'name': 'Aarav',
            'role': 'buyer',
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('FSSAI details'), findsNothing);
    expect(find.text('Seller Settings'), findsNothing);
  });
}
