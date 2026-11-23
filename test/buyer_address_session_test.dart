import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/widgets/buyer_address_list.dart';

void main() {
  testWidgets('a saved profile without a login token asks to sign in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerAddressList(
            initialSocietyName: 'The White House',
            initialFlatNumber: '5555',
            loadAddresses: () async {
              loads += 1;
              throw Exception('Missing or invalid Authorization header');
            },
            selectAddress: (_) async => {},
            deleteAddress: (_) async => {},
            onAdd: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('The White House'), findsWidgets);
    expect(find.text('Sign in to manage addresses'), findsOneWidget);
    expect(find.textContaining('Authorization'), findsNothing);
    expect(loads, 0);
  });
}
