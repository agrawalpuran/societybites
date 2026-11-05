import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/services/api_service.dart';

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

Map<String, dynamic> _sellerMe({
  String level = 'MY_SOCIETY',
  double? nearby,
  double? extended,
  String? cityKey = 'bengaluru',
}) {
  return {
    'id': 'seller-1',
    'name': 'Anita',
    'phone': '+919901844776',
    'role': 'seller',
    'sellingReachLevel': level,
    'fulfilmentMode': 'BUYER_PICKUP',
    'fulfilment': {'mode': 'BUYER_PICKUP', 'deliveryCharge': null},
    'sellingReach': {
      'cityKey': cityKey,
      'nearbyRadiusKm': nearby,
      'extendedRadiusKm': extended,
      'maxSellerRadiusKm': extended ?? nearby ?? 10,
    },
    'society': {'name': 'Prestige Notting Hill'},
    'flat': {'flatNumber': '3062'},
  };
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required Map<String, dynamic> profile,
  Future<Map<String, dynamic>> Function({
    String? sellingReachLevel,
    int? sellingReachRadiusKm,
    String? fulfilmentMode,
    double? deliveryCharge,
    double? deliveryChargeInSociety,
    double? deliveryChargeNearby,
    double? deliveryChargeExtended,
    String? paymentPreference,
    String? kitchenOpensAt,
    String? kitchenClosesAt,
    bool? clearKitchenHours,
    bool? hideFlatNumber,
  })? updateProfile,
}) async {
  SharedPreferences.setMockInitialValues({
    'user_id': 'seller-1',
    'user_role': profile['role'] as String? ?? 'seller',
    'user_name': profile['name'] as String? ?? 'Anita',
    'phone': profile['phone'] as String? ?? '+919901844776',
  });
  await tester.binding.setSurfaceSize(const Size(800, 2000));
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        fetchProfile: () async => profile,
        updateProfile: updateProfile,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  while (tester.takeException() != null) {}
}

Future<void> _openSellerSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Seller Settings'));
  await tester.tap(find.text('Seller Settings'));
  await tester.pumpAndSettle();
  while (tester.takeException() != null) {}
}

Future<void> _openSellingReachSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Selling Reach'));
  await tester.tap(find.text('Selling Reach'));
  await tester.pumpAndSettle();
  while (tester.takeException() != null) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _ignoreKnownLayoutNoise();
    ApiService.previewSellingReachChangeForTest =
        ({required sellingReachLevel, sellingReachRadiusKm}) async =>
            {'allowed': true};
  });

  tearDown(() {
    ApiService.previewSellingReachChangeForTest = null;
  });

  testWidgets('seller sees configured radius labels and can change reach', (
    tester,
  ) async {
    var savedLevel = 'MY_SOCIETY';
    int? savedRadius;
    await _pumpProfile(
      tester,
      profile: _sellerMe(nearby: 5, extended: 10),
      updateProfile: (({
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
        savedLevel = sellingReachLevel ?? savedLevel;
        savedRadius = sellingReachRadiusKm;
        return _sellerMe(
          level: savedLevel,
          nearby: 5,
          extended: 10,
        );
      }),
    );

    expect(find.text('Seller Settings'), findsOneWidget);
    expect(find.byKey(const Key('profile-edit-button')), findsOneWidget);
    expect(find.text('SELLER FULFILMENT'), findsNothing);
    expect(find.text('PAYMENT METHODS'), findsNothing);

    await _openSellerSettings(tester);
    expect(find.text('PAYMENTS'), findsOneWidget);
    expect(find.text('Selling Reach'), findsOneWidget);
    expect(find.text('Visible to buyers in your society'), findsOneWidget);

    await _openSellingReachSheet(tester);

    expect(find.text('Selling reach'), findsOneWidget);
    expect(find.text('Who can discover and order from you?'), findsOneWidget);
    expect(find.text('My society'), findsOneWidget);
    expect(find.text('Beyond your society'), findsOneWidget);

    await tester.tap(find.text('Beyond your society'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}

    expect(savedLevel, 'BEYOND_SOCIETY');
    expect(savedRadius, 5);
    expect(find.text('Buyers in your society and within 5 km'), findsOneWidget);
    expect(find.text('Selling reach updated'), findsOneWidget);
  });

  testWidgets('failed save keeps previous selling reach selection', (tester) async {
    await _pumpProfile(
      tester,
      profile: _sellerMe(nearby: 5, extended: 10),
      updateProfile: (({
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
        throw Exception('city config missing');
      }),
    );

    await _openSellerSettings(tester);
    await _openSellingReachSheet(tester);
    await tester.tap(find.text('Beyond your society'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    while (tester.takeException() != null) {}

    expect(find.text('Visible to buyers in your society'), findsOneWidget);
    expect(find.text('Buyers in your society and within 5 km'), findsNothing);
    expect(find.textContaining('Could not update selling reach'), findsOneWidget);
  });

  testWidgets('Beyond your society stays disabled when city is unavailable', (
    tester,
  ) async {
    var updateCalls = 0;
    await _pumpProfile(
      tester,
      profile: _sellerMe(cityKey: null),
      updateProfile: (({
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
        updateCalls++;
        return _sellerMe(level: sellingReachLevel ?? 'MY_SOCIETY');
      }),
    );

    await _openSellerSettings(tester);
    await _openSellingReachSheet(tester);

    expect(find.text('Not available in your city yet'), findsWidgets);

    await tester.tap(find.text('Beyond your society'));
    await tester.pumpAndSettle();

    expect(updateCalls, 0);
    expect(find.text('Who can discover and order from you?'), findsOneWidget);
  });

  testWidgets('buyer profile still shows Start Selling and not Selling Reach', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'buyer-1',
      'user_role': 'buyer',
      'user_name': 'Puran',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'buyer-1',
            'name': 'Puran',
            'role': 'buyer',
            'sellingReachLevel': 'MY_SOCIETY',
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    expect(find.text('Start Selling'), findsOneWidget);
    expect(find.text('Seller Settings'), findsNothing);
    expect(find.text('PAYMENT METHODS'), findsNothing);
    expect(find.byKey(const Key('profile-edit-button')), findsOneWidget);
  });
}
