import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/profile_screen.dart';

Map<String, dynamic> _home({bool selected = true}) {
  return {
    'id': 'home',
    'label': 'Home',
    'selected': selected,
    'societyId': 'society-home',
    'flatId': 'flat-home',
    'block': 'A',
    'flatNumber': '3062',
    'society': {'id': 'society-home', 'name': 'Palm Meadows', 'city': 'Bengaluru'},
  };
}

Map<String, dynamic> _office({bool selected = false}) {
  return {
    'id': 'office',
    'label': 'Office',
    'selected': selected,
    'societyId': 'society-office',
    'flatId': null,
    'block': null,
    'flatNumber': null,
    'society': {'id': 'society-office', 'name': 'RMZ Ecoworld', 'city': 'Bengaluru'},
  };
}

void main() {
  testWidgets('buyer chooses a saved place with the radio', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'buyer-1',
      'user_role': 'buyer',
      'user_name': 'Ananya',
      'society_id': 'society-home',
      'society_name': 'Palm Meadows',
      'flat_id': 'flat-home',
      'flat_number': '3062',
    });
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selects = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'buyer-1',
            'name': 'Ananya',
            'role': 'buyer',
            'phone': '+919845011220',
            'societyId': 'society-home',
            'flatId': 'flat-home',
            'society': {'id': 'society-home', 'name': 'Palm Meadows'},
            'flat': {'id': 'flat-home', 'flatNumber': '3062'},
          },
          fetchBuyerAddresses: () async => {
            'addresses': [_home(), _office()],
          },
          selectBuyerAddress: (id) async {
            selects += 1;
            expect(id, 'office');
            return {
              'addresses': [_home(selected: false), _office(selected: true)],
              'place': {
                'societyId': 'society-office',
                'flatId': null,
                'society': {
                  'id': 'society-office',
                  'name': 'RMZ Ecoworld',
                  'city': 'Bengaluru',
                },
                'flat': null,
              },
            };
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Addresses'), findsOneWidget);
    expect(find.text('Showing food near Palm Meadows.'), findsOneWidget);
    expect(find.text('Flat 3062'), findsWidgets);
    expect(find.byKey(const Key('buyer-address-remove-home')), findsNothing);
    expect(find.byKey(const Key('buyer-address-remove-office')), findsOneWidget);

    await tester.tap(find.byKey(const Key('buyer-address-home')));
    await tester.pump();
    expect(selects, 0);

    await tester.tap(find.byKey(const Key('buyer-address-office')));
    await tester.pump();
    await tester.pump();

    expect(selects, 1);
    expect(find.text('Showing food near RMZ Ecoworld.'), findsOneWidget);
    expect(find.text('RMZ Ecoworld'), findsWidgets);
    expect(find.text('Flat 3062'), findsNothing);
  });

  testWidgets('seller profile has no saved places', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'seller-1',
            'name': 'Anita',
            'role': 'seller',
            'sellingReachLevel': 'MY_SOCIETY',
            'fulfilmentMode': 'BUYER_PICKUP',
            'society': {'name': 'Palm Meadows'},
            'flat': {'flatNumber': '3062'},
          },
          fetchBuyerAddresses: () async => throw StateError('seller must not load places'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Addresses'), findsNothing);
    expect(find.text('Add address'), findsNothing);
  });
}
