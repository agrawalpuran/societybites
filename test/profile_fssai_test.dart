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

    String? savedNumber;
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
          saveFssaiDetails: ({
            required fssaiNumber,
            fssaiRegisteredName,
            fssaiExpiry,
          }) async {
            savedNumber = fssaiNumber;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('FSSAI details'), findsOneWidget);
    await tester.ensureVisible(find.text('FSSAI details'));
    await tester.tap(find.text('FSSAI details'));
    await tester.pumpAndSettle();
    expect(find.text('FSSAI registration number'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'FSSAI registration number'),
      '12345678901234',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedNumber, '12345678901234');
    expect(find.textContaining('12345678901234'), findsWidgets);
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

    expect(find.textContaining('12345678901234'), findsWidgets);
    expect(find.textContaining('Agrawal Kitchen'), findsWidgets);

    await tester.ensureVisible(find.text('FSSAI details'));
    await tester.tap(find.text('FSSAI details'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Saved licence 12345678901234'),
      findsOneWidget,
    );
    expect(find.text('12345678901234'), findsWidgets);
    expect(find.text('Agrawal Kitchen'), findsWidgets);
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
    expect(find.text('FSSAI details'), findsNothing);
  });
}
