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
}) {
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
      'deliveryCharge':
          fulfilmentMode == 'BUYER_PICKUP' ? null : deliveryCharge,
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
        deliveryCharge: 40,
      ).subtitle,
      '₹40 delivery charge',
    );
  });

  testWidgets('seller profile shows fulfilment and can save seller delivery', (
    tester,
  ) async {
    var savedMode = 'BUYER_PICKUP';
    double? savedCharge;
    await _pumpSeller(
      tester,
      profile: _sellerMe(),
      updateProfile: ({
        sellingReachLevel,
        fulfilmentMode,
        deliveryCharge,
        paymentPreference,
      }) async {
        savedMode = fulfilmentMode ?? savedMode;
        savedCharge = deliveryCharge ?? savedCharge;
        return _sellerMe(fulfilmentMode: savedMode, deliveryCharge: savedCharge);
      },
    );

    expect(find.text('SELLER FULFILMENT'), findsOneWidget);
    expect(find.text('PAYMENT METHODS'), findsOneWidget);
    expect(find.text('UPI + Cash on Delivery'), findsOneWidget);
    expect(find.text('Buyer Pickup'), findsOneWidget);
    expect(find.text('SELLER SETTINGS'), findsOneWidget);
    expect(find.text('My Society'), findsOneWidget);

    await tester.ensureVisible(_fulfilmentChange());
    await tester.tap(_fulfilmentChange());
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(find.text('How will buyers receive their orders?'), findsOneWidget);
    expect(find.text('Buyer collects the order from you.'), findsWidgets);
    await tester.tap(find.text('Seller Delivery'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery charge'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '40');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(savedMode, 'SELLER_DELIVERY');
    expect(savedCharge, 40);
    expect(find.text('Seller Delivery'), findsOneWidget);
    expect(find.text('₹40 delivery charge'), findsOneWidget);
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
        paymentPreference,
      }) async {
        throw Exception('rejected');
      },
    );

    await tester.ensureVisible(_fulfilmentChange());
    await tester.tap(_fulfilmentChange());
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
    await tester.tap(find.text('Both'));
    await tester.pumpAndSettle();
    expect(find.text('Delivery charge'), findsOneWidget);
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
    expect(find.text('SELLER SETTINGS'), findsNothing);
  });
}
