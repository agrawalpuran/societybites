import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/seller_terms.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/screens/seller_settings_screen.dart';
import 'package:societybites/screens/seller_terms_screen.dart';
import 'package:societybites/services/seller_onboarding.dart';

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

Map<String, dynamic> _buyerProfile() {
  return {
    'id': 'buyer-1',
    'name': 'Puran',
    'phone': '+919900000001',
    'role': 'buyer',
    'sellingReachLevel': 'MY_SOCIETY',
    'fulfilmentMode': 'BUYER_PICKUP',
    'paymentPreference': 'UPI_AND_COD',
    'society': {'name': 'Prestige Notting Hill'},
    'flat': {'flatNumber': '101'},
    'fssai': {
      'requirementEnabled': false,
      'status': 'NOT_SUBMITTED',
      'assistanceRequested': true,
      'canEnableSellingDespiteFssai': true,
      'canSellDespiteFssai': true,
    },
  };
}

Future<void> _openFirstTimeSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Start Selling'));
  await tester.tap(find.text('Start Selling'));
  await tester.pumpAndSettle();
  while (tester.takeException() != null) {}
}

Future<void> _enterSellerUpi(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('seller-setup-upi-id')),
    'seller@oksbi',
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const Key('seller-setup-upi-display-name')),
    'Seller',
  );
  await tester.pump();
}

Future<void> _confirmUpiDialogIfShown(WidgetTester tester) async {
  await tester.pumpAndSettle();
  if (find.byKey(const Key('confirm-upi-id-checkbox')).evaluate().isEmpty) {
    return;
  }
  await tester.tap(find.byKey(const Key('confirm-upi-id-checkbox')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('confirm-upi-id-save')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _ignoreKnownLayoutNoise();
    SellerOnboarding.resetPendingKitchenWelcome();
    SharedPreferences.setMockInitialValues({
      'user_id': 'buyer-1',
      'user_role': 'buyer',
      'user_name': 'Puran',
    });
  });

  testWidgets('Submit stays disabled until proof and both declarations are set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SellerTermsScreen(
          initialDocumentBytes: Uint8List.fromList([1, 2, 3]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seller Terms & Conditions'), findsOneWidget);
    expect(find.text('Take Photo'), findsNothing);
    expect(find.text('Replace'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('seller-terms-accept')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const Key('seller-terms-agree')));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byKey(const Key('seller-terms-accept'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('seller-terms-declaration')));
    await tester.pump();

    final enabled = tester.widget<ElevatedButton>(
      find.byKey(const Key('seller-terms-accept')),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('first-time seller reviews settings, then accepts terms to enable', (
    tester,
  ) async {
    Map<String, dynamic>? sent;
    var profileSaves = 0;
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => _buyerProfile(),
          startSelling: (context) async => true,
          updateProfile: ({
            sellingReachLevel,
            sellingReachRadiusKm,
            fulfilmentMode,
            deliveryCharge,
            deliveryChargeInSociety,
            deliveryChargeNearby,
            deliveryChargeExtended,
            paymentPreference,
            kitchenOpensAt,
            kitchenClosesAt,
            clearKitchenHours,
            hideFlatNumber,
          }) async {
            profileSaves += 1;
            return {
              'role': 'seller',
              'paymentPreference': paymentPreference,
              'sellingReachLevel': 'MY_SOCIETY',
              'fulfilmentMode': 'BUYER_PICKUP',
            };
          },
          acceptSellerTerms: (body) async {
            sent = body;
            return {
              'role': 'seller',
              'paymentPreference': body['paymentPreference'],
              'sellingReachLevel': 'MY_SOCIETY',
              'fulfilmentMode': 'BUYER_PICKUP',
            };
          },
          uploadAddressProof: (_, __) async => 'https://example.com/proof.jpg',
          buildSellerTermsScreen: () => SellerTermsScreen(
            initialDocumentBytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    await _openFirstTimeSettings(tester);
    expect(find.byType(SellerSettingsScreen), findsOneWidget);
    expect(find.text('Cash on Delivery in society, UPI outside'), findsOneWidget);
    expect(find.byKey(const Key('seller-setup-upi-id')), findsOneWidget);
    expect(find.text('My society'), findsOneWidget);
    expect(find.textContaining('FSSAI details'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Payment Methods'), findsNothing);
    expect(profileSaves, 0);

    await tester.tap(find.text('UPI Only'));
    await tester.pumpAndSettle();

    expect(find.text('UPI Only'), findsWidgets);
    expect(profileSaves, 0);
    expect(sent, isNull);

    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('seller-settings-enable')))
          .onPressed,
      isNotNull,
    );
    await _enterSellerUpi(tester);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('seller-settings-enable')));
    await tester.tap(find.byKey(const Key('seller-settings-enable')));
    await _confirmUpiDialogIfShown(tester);
    expect(find.byType(SellerTermsScreen), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byKey(const Key('seller-terms-accept'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('seller-terms-decline')));
    await tester.pumpAndSettle();
    expect(find.byType(SellerSettingsScreen), findsOneWidget);
    expect(find.byType(SellerTermsScreen), findsNothing);
    expect(sent, isNull);

    await tester.ensureVisible(find.byKey(const Key('seller-settings-enable')));
    await tester.tap(find.byKey(const Key('seller-settings-enable')));
    await _confirmUpiDialogIfShown(tester);
    await tester.tap(find.byKey(const Key('seller-terms-accept')));
    await tester.pumpAndSettle();
    expect(find.byType(SellerTermsScreen), findsOneWidget);
    expect(sent, isNull);

    await tester.tap(find.byKey(const Key('seller-terms-declaration')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('seller-terms-agree')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('seller-terms-accept')));
    await tester.pumpAndSettle();

    expect(sent, isNotNull);
    expect(sent!['addressProofUrl'], 'https://example.com/proof.jpg');
    expect(sent!['termsVersion'], sellerTermsVersion);
    expect(sent!['termsVersion'], '1.0');
    expect(sent!.containsKey('acceptedAt'), isFalse);
    expect(sent!['paymentPreference'], 'UPI_ONLY');
    expect(find.byType(SellerTermsScreen), findsNothing);
    expect(find.byType(SellerSettingsScreen), findsNothing);
    expect(SellerOnboarding.peekPendingKitchenWelcome(), isTrue);
    expect(profileSaves, 1);
  });

  testWidgets('existing sellers open Seller Settings without a terms gate', (
    tester,
  ) async {
    var profileSaves = 0;
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'seller-1',
            'name': 'Puran',
            'role': 'seller',
            'paymentPreference': 'UPI_AND_COD',
            'sellingReachLevel': 'MY_SOCIETY',
            'fulfilmentMode': 'BUYER_PICKUP',
          },
          updateProfile: ({
            sellingReachLevel,
            sellingReachRadiusKm,
            fulfilmentMode,
            deliveryCharge,
            deliveryChargeInSociety,
            deliveryChargeNearby,
            deliveryChargeExtended,
            paymentPreference,
            kitchenOpensAt,
            kitchenClosesAt,
            clearKitchenHours,
            hideFlatNumber,
          }) async {
            profileSaves += 1;
            return {
              'role': 'seller',
              'paymentPreference': paymentPreference,
              'sellingReachLevel': 'MY_SOCIETY',
              'fulfilmentMode': 'BUYER_PICKUP',
            };
          },
          acceptSellerTerms: (body) async {
            fail('existing sellers must not be asked to accept terms');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    expect(find.text('Start Selling'), findsNothing);
    await tester.ensureVisible(find.text('Seller Settings'));
    await tester.tap(find.text('Seller Settings'));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(find.byType(SellerSettingsScreen), findsOneWidget);
    expect(find.text('Save / Enable Selling'), findsNothing);
    expect(find.byType(SellerTermsScreen), findsNothing);

    await tester.tap(find.text('Payment Methods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UPI Only'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(profileSaves, 1);
  });
}
