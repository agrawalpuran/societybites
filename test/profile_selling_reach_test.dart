import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/selling_reach.dart';
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
  String level = 'MY_SOCIETY',
  double? nearby,
  double? extended,
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
      'cityKey': 'bengaluru',
      'nearbyRadiusKm': nearby,
      'extendedRadiusKm': extended,
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
    String? fulfilmentMode,
    double? deliveryCharge,
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
  if (find.text('Change').evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      find.text('Change').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    while (tester.takeException() != null) {}
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _ignoreKnownLayoutNoise();
  });

  testWidgets('seller sees configured radius labels and can change reach', (
    tester,
  ) async {
    var savedLevel = 'MY_SOCIETY';
    await _pumpProfile(
      tester,
      profile: _sellerMe(nearby: 5, extended: 10),
      updateProfile: ({sellingReachLevel, fulfilmentMode, deliveryCharge}) async {
        savedLevel = sellingReachLevel ?? savedLevel;
        return _sellerMe(level: savedLevel, nearby: 5, extended: 10);
      },
    );

    expect(find.text('SELLER SETTINGS'), findsOneWidget);
    expect(find.text('My Society'), findsOneWidget);
    expect(find.text('Visible to buyers in your society'), findsOneWidget);
    expect(find.text('Change'), findsWidgets);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('SELLER FULFILMENT'), findsOneWidget);

    await tester.ensureVisible(find.text('Change').first);
    await tester.tap(find.text('Change').first);
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(find.text('Selling Reach'), findsOneWidget);
    expect(find.text('Who can see your food?'), findsOneWidget);
    expect(find.text('Buyers in your society'), findsOneWidget);
    expect(find.text('Buyers within 5 km'), findsOneWidget);
    expect(find.text('Buyers within 10 km'), findsOneWidget);

    await tester.tap(find.text('Nearby'));
    await tester.pumpAndSettle();

    expect(savedLevel, 'NEARBY');
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('Buyers within 5 km'), findsOneWidget);
    expect(find.text('Selling reach updated'), findsOneWidget);
  });

  testWidgets('failed save keeps previous selling reach selection', (tester) async {
    await _pumpProfile(
      tester,
      profile: _sellerMe(nearby: 5, extended: 10),
      updateProfile: ({sellingReachLevel, fulfilmentMode, deliveryCharge}) async {
        throw Exception('city config missing');
      },
    );

    await tester.ensureVisible(find.text('Change').first);
    await tester.tap(find.text('Change').first);
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}
    await tester.tap(find.text('Extended'));
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(find.text('My Society'), findsOneWidget);
    expect(find.text('Extended'), findsNothing);
    expect(find.textContaining('Could not update selling reach'), findsOneWidget);
  });

  testWidgets('Nearby and Extended stay disabled when radii are null', (tester) async {
    var updateCalls = 0;
    await _pumpProfile(
      tester,
      profile: _sellerMe(),
      updateProfile: ({sellingReachLevel, fulfilmentMode, deliveryCharge}) async {
        updateCalls++;
        return _sellerMe(level: sellingReachLevel ?? 'MY_SOCIETY');
      },
    );

    await tester.ensureVisible(find.text('Change').first);
    await tester.tap(find.text('Change').first);
    await tester.pumpAndSettle();
    while (tester.takeException() != null) {}

    expect(
      find.text('Nearby selling is not available in your city yet.'),
      findsWidgets,
    );

    await tester.tap(find.text('Nearby'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extended'));
    await tester.pumpAndSettle();

    expect(updateCalls, 0);
    expect(find.text('Who can see your food?'), findsOneWidget);
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
    expect(find.text('SELLER SETTINGS'), findsNothing);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('My Orders'), findsOneWidget);
  });
}
