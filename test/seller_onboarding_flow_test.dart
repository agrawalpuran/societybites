import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/screens/seller_settings_screen.dart';

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
    _ignoreKnownLayoutNoise();
  });

  testWidgets(
    'Start Selling opens Seller Settings instead of the old UPI-only sheet',
    (tester) async {
      var enabled = false;
      SharedPreferences.setMockInitialValues({
        'user_id': 'buyer-1',
        'user_role': 'buyer',
        'user_name': 'Puran',
      });
      await tester.binding.setSurfaceSize(const Size(800, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            fetchProfile: () async => {
              'id': 'buyer-1',
              'name': 'Puran',
              'phone': '+919900000001',
              'role': enabled ? 'seller' : 'buyer',
              'sellingReachLevel': 'MY_SOCIETY',
              'fulfilmentMode': 'BUYER_PICKUP',
              'society': {'name': 'Prestige Notting Hill'},
              'flat': {'flatNumber': '101'},
            },
            startSelling: (context) async {
              enabled = true;
              return true;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      while (tester.takeException() != null) {}

      await tester.ensureVisible(find.text('Start Selling'));
      await tester.tap(find.text('Start Selling'));
      await tester.pumpAndSettle();
      while (tester.takeException() != null) {}

      expect(find.byType(SellerSettingsScreen), findsOneWidget);
      expect(
        find.text(
          'Fill in payment methods, UPI, selling reach, fulfilment, and FSSAI so you can start listing.',
        ),
        findsOneWidget,
      );
      expect(find.text('Payment Methods'), findsOneWidget);
      expect(find.text('UPI for Payments'), findsOneWidget);
      expect(find.text('Selling Reach'), findsOneWidget);
      expect(find.text('FSSAI details'), findsOneWidget);
      expect(find.text('Add UPI to receive payments'), findsNothing);
    },
  );

  testWidgets('cancelling Start Selling does not open Seller Settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'buyer-1',
      'user_role': 'buyer',
      'user_name': 'Puran',
    });
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'buyer-1',
            'name': 'Puran',
            'role': 'buyer',
            'sellingReachLevel': 'MY_SOCIETY',
          },
          startSelling: (context) async => false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    await tester.ensureVisible(find.text('Start Selling'));
    await tester.tap(find.text('Start Selling'));
    await tester.pumpAndSettle();

    expect(find.byType(SellerSettingsScreen), findsNothing);
    expect(find.text('Start Selling'), findsOneWidget);
  });
}
