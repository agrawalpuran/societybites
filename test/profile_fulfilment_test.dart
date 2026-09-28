import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/seller_fulfilment.dart';
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

Map<String, dynamic> _sellerMe({
  String fulfilmentMode = 'BUYER_PICKUP',
  double? deliveryCharge,
  double? deliveryChargeInSociety,
  double? deliveryChargeNearby,
  double? deliveryChargeExtended,
}) {
  final nearby = deliveryChargeNearby ?? deliveryCharge;
  final extended = deliveryChargeExtended ?? nearby;
  final inSociety = deliveryChargeInSociety ?? 0;
  final offersDelivery = fulfilmentMode != 'BUYER_PICKUP';
  return {
    'id': 'seller-1',
    'name': 'Anita',
    'phone': '+919901844776',
    'role': 'seller',
    'sellingReachLevel': 'MY_SOCIETY',
    'sellingReach': {
      'cityKey': 'bengaluru',
      'nearbyRadiusKm': 5,
      'extendedRadiusKm': 10,
    },
    'fulfilmentMode': fulfilmentMode,
    'fulfilment': {
      'mode': fulfilmentMode,
      'deliveryCharge': offersDelivery ? nearby : null,
      'deliveryChargeInSociety': offersDelivery ? inSociety : null,
      'deliveryChargeNearby': offersDelivery ? nearby : null,
      'deliveryChargeExtended': offersDelivery ? extended : null,
    },
    'society': {'name': 'Prestige Notting Hill'},
    'flat': {'flatNumber': '3062'},
  };
}

Future<void> _pumpSeller(
  WidgetTester tester, {
  required Map<String, dynamic> profile,
  Future<Map<String, dynamic>> Function({
    String? sellingReachLevel,
    String? fulfilmentMode,
    double? deliveryCharge,
    double? deliveryChargeInSociety,
    double? deliveryChargeNearby,
    double? deliveryChargeExtended,
    String? paymentPreference,
  })? updateProfile,
}) async {
  SharedPreferences.setMockInitialValues({
    'user_id': 'seller-1',
    'user_role': 'seller',
    'user_name': 'Anita',
    'phone': '+919901844776',
  });
  await tester.binding.setSurfaceSize(const Size(800, 2200));
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

Finder _fulfilmentChange() => find.text('Change').last;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_ignoreKnownLayoutNoise);

  test('parses fulfilment modes and labels', () {
    expect(parseFulfilmentMode('BUYER_PICKUP').title, 'Buyer Pickup');
    expect(parseFulfilmentMode('SELLER_DELIVERY').title, 'Seller Delivery');
    expect(parseFulfilmentMode('BOTH').title, 'Pickup + Seller Delivery');
    expect(FulfilmentMode.buyerPickup.showsDeliveryCharge, isFalse);
    expect(FulfilmentMode.sellerDelivery.showsDeliveryCharge, isTrue);
    expect(FulfilmentMode.both.showsDeliveryCharge, isTrue);
    expect(
      const SellerFulfilment(
        mode: FulfilmentMode.sellerDelivery,
        deliveryChargeInSociety: 0,
        deliveryChargeNearby: 40,
        deliveryChargeExtended: 60,
      ).subtitle,
      'In society ₹0 · Nearby ₹40 · Extended ₹60',
    );
    expect(
      const SellerFulfilment(
        mode: FulfilmentMode.sellerDelivery,
        deliveryChargeNearby: 40,
      ).chargeForBuyer(sameSociety: true),
      0,
    );
    expect(
      const SellerFulfilment(
        mode: FulfilmentMode.sellerDelivery,
        deliveryChargeNearby: 40,
      ).chargeForBuyer(sameSociety: false),
      40,
    );
  });

  testWidgets('seller profile shows fulfilment and can save seller delivery', (
    tester,
  ) async {
    var savedMode = 'BUYER_PICKUP';
    double? savedNearby;
    double? savedInSociety;
    double? savedExtended;
    await _pumpSeller(
      tester,
      profile: _sellerMe(),
      updateProfile: ({
        sellingReachLevel,
        fulfilmentMode,
        deliveryCharge,
        deliveryChargeInSociety,
        deliveryChargeNearby,
        deliveryChargeExtended,
        paymentPreference,
      }) async {
        savedMode = fulfilmentMode ?? savedMode;
        savedNearby = deliveryChargeNearby ?? deliveryCharge ?? savedNearby;
        savedInSociety = deliveryChargeInSociety ?? savedInSociety;
        savedExtended = deliveryChargeExtended ?? savedExtended;
        return _sellerMe(
          fulfilmentMode: savedMode,
          deliveryCharge: savedNearby,
          deliveryChargeInSociety: savedInSociety,
          deliveryChargeNearby: savedNearby,
          deliveryChargeExtended: savedExtended,
        );
      },
    );

    await _openSellerSettings(tester);
    expect(find.text('PAYMENTS'), findsOneWidget);
    expect(find.text('Payment Methods'), findsOneWidget);
    expect(find.text('Cash on Delivery in society, UPI outside'), findsOneWidget);
    expect(find.text('Buyer Pickup'), findsOneWidget);
    expect(find.text('Selling Reach'), findsOneWidget);

    await tester.ensureVisible(_fulfilmentChange());
    await tester.tap(_fulfilmentChange());
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(find.text('How will buyers receive their orders?'), findsOneWidget);
    expect(find.text('Buyer collects the order from you.'), findsWidgets);
    await tester.tap(find.text('Seller Delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery charges'), findsOneWidget);
    expect(find.text('In society'), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Extended'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('fulfilment-save')),
        matching: find.byType(SafeArea),
      ),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byKey(const Key('fulfilment-save')),
      ),
      findsNothing,
    );

    await tester.enterText(find.byKey(const Key('delivery-charge-nearby')), '40');
    await tester.enterText(
      find.byKey(const Key('delivery-charge-extended')),
      '60',
    );
    await tester.ensureVisible(find.byKey(const Key('fulfilment-save')));
    await tester.tap(find.byKey(const Key('fulfilment-save')));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(savedMode, 'SELLER_DELIVERY');
    expect(savedInSociety, 0);
    expect(savedNearby, 40);
    expect(savedExtended, 60);
    expect(find.text('Seller Delivery'), findsOneWidget);
    expect(
      find.text('In society ₹0 · Nearby ₹40 · Extended ₹60'),
      findsOneWidget,
    );
    expect(find.text('Fulfilment updated'), findsOneWidget);
  });

  testWidgets('Both shows delivery charge and failed save keeps previous', (
    tester,
  ) async {
    await _pumpSeller(
      tester,
      profile: _sellerMe(),
      updateProfile: ({
        sellingReachLevel,
        fulfilmentMode,
        deliveryCharge,
        deliveryChargeInSociety,
        deliveryChargeNearby,
        deliveryChargeExtended,
        paymentPreference,
      }) async {
        throw Exception('rejected');
      },
    );

    await _openSellerSettings(tester);
    await tester.ensureVisible(_fulfilmentChange());
    await tester.tap(_fulfilmentChange());
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
    await tester.tap(find.text('Both'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery charges'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(find.text('Buyer Pickup'), findsOneWidget);
    expect(find.text('Pickup + Seller Delivery'), findsNothing);
    expect(find.textContaining('Could not update fulfilment'), findsOneWidget);
  });

  testWidgets('buyer profile does not show fulfilment controls', (tester) async {
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
            'fulfilmentMode': 'BUYER_PICKUP',
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    expect(find.text('Start Selling'), findsOneWidget);
    expect(find.text('SELLER FULFILMENT'), findsNothing);
    expect(find.text('PAYMENT METHODS'), findsNothing);
    expect(find.text('Seller Settings'), findsNothing);
  });
}
