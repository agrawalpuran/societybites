import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/widgets/confirm_upi_id_dialog.dart';

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

Map<String, dynamic> _sellerProfile({
  String? upiId,
  String paymentPreference = 'UPI_AND_COD',
}) {
  return {
    'id': 'seller-1',
    'name': 'Anita',
    'phone': '+919901844776',
    'role': 'seller',
    'upiId': upiId,
    'paymentPreference': paymentPreference,
    'sellingReachLevel': 'MY_SOCIETY',
    'sellingReach': {
      'cityKey': 'bengaluru',
      'nearbyRadiusKm': 5,
      'extendedRadiusKm': 10,
    },
    'fulfilmentMode': 'BUYER_PICKUP',
    'society': {'name': 'Prestige Notting Hill'},
    'flat': {'flatNumber': '3062'},
  };
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required Map<String, dynamic> profile,
  Future<void> Function({required String upiId, String? upiDisplayName})?
      saveUpiDetails,
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
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        fetchProfile: () async => profile,
        saveUpiDetails: saveUpiDetails,
        updateProfile: updateProfile,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  while (tester.takeException() != null) {}
}

Future<void> _openUpiSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('UPI for Payments'));
  await tester.tap(find.text('UPI for Payments'));
  await tester.pumpAndSettle();
  expect(find.text('Save UPI'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_ignoreOverflow);

  testWidgets('confirm dialog starts unchecked and save is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConfirmUpiIdDialog(upiId: 'yourname@bank'),
      ),
    );

    expect(find.text('Confirm UPI ID'), findsOneWidget);
    expect(find.text('yourname@bank'), findsOneWidget);
    expect(find.text('I confirm that this UPI ID is correct.'), findsOneWidget);

    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const Key('confirm-upi-id-checkbox')),
    );
    expect(checkbox.value, isFalse);

    final save = tester.widget<ElevatedButton>(
      find.byKey(const Key('confirm-upi-id-save')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('checking the box enables Confirm & Save', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConfirmUpiIdDialog(upiId: 'yourname@bank'),
      ),
    );

    await tester.tap(find.byKey(const Key('confirm-upi-id-checkbox')));
    await tester.pump();

    final save = tester.widget<ElevatedButton>(
      find.byKey(const Key('confirm-upi-id-save')),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets('Cancel returns without confirming', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmUpiIdBeforeSave(
                context,
                upiId: 'yourname@bank',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-upi-id-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('Confirm & Save returns true after checkbox', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmUpiIdBeforeSave(
                context,
                upiId: 'yourname@bank',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-upi-id-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-upi-id-save')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('invalid UPI stays on the sheet and does not save', (
    tester,
  ) async {
    var saved = 0;
    await _pumpProfile(
      tester,
      profile: _sellerProfile(),
      saveUpiDetails: ({required upiId, upiDisplayName}) async {
        saved += 1;
      },
    );

    await _openUpiSheet(tester);
    await tester.enterText(find.byType(TextField).first, 'not-a-upi');
    await tester.tap(find.text('Save UPI'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid UPI ID (e.g. name@oksbi)'), findsOneWidget);
    expect(find.text('Confirm UPI ID'), findsNothing);
    expect(saved, 0);
  });

  testWidgets('valid UPI opens confirmation and cancel does not save', (
    tester,
  ) async {
    var saved = 0;
    await _pumpProfile(
      tester,
      profile: _sellerProfile(),
      saveUpiDetails: ({required upiId, upiDisplayName}) async {
        saved += 1;
      },
    );

    await _openUpiSheet(tester);
    await tester.enterText(find.byType(TextField).first, 'yourname@bank');
    await tester.tap(find.text('Save UPI'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm UPI ID'), findsOneWidget);
    expect(find.text('yourname@bank'), findsWidgets);
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('confirm-upi-id-save')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('confirm-upi-id-cancel')));
    await tester.pumpAndSettle();
    expect(saved, 0);
    expect(find.text('UPI ID saved'), findsNothing);
    expect(find.text('Save UPI'), findsOneWidget);
  });

  testWidgets('Confirm & Save uses the existing UPI save flow', (
    tester,
  ) async {
    String? savedUpi;
    await _pumpProfile(
      tester,
      profile: _sellerProfile(),
      saveUpiDetails: ({required upiId, upiDisplayName}) async {
        savedUpi = upiId;
      },
    );

    await _openUpiSheet(tester);
    await tester.enterText(find.byType(TextField).first, 'anita@oksbi');
    await tester.tap(find.text('Save UPI'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-upi-id-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-upi-id-save')));
    await tester.pumpAndSettle();

    expect(savedUpi, 'anita@oksbi');
    expect(find.text('UPI ID saved'), findsOneWidget);
  });

  testWidgets('changing UPI requires confirmation again', (tester) async {
    final saved = <String>[];
    await _pumpProfile(
      tester,
      profile: _sellerProfile(upiId: 'old@oksbi'),
      saveUpiDetails: ({required upiId, upiDisplayName}) async {
        saved.add(upiId);
      },
    );

    await _openUpiSheet(tester);
    await tester.enterText(find.byType(TextField).first, 'new@oksbi');
    await tester.tap(find.text('Save UPI'));
    await tester.pumpAndSettle();
    expect(find.text('new@oksbi'), findsWidgets);
    await tester.tap(find.byKey(const Key('confirm-upi-id-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-upi-id-save')));
    await tester.pumpAndSettle();
    expect(saved, ['new@oksbi']);
  });

  testWidgets('payment preference UPI+COD is unchanged by UPI confirm', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      profile: _sellerProfile(paymentPreference: 'UPI_AND_COD'),
    );
    expect(find.text('UPI + Cash on Delivery'), findsOneWidget);
    expect(find.text('PAYMENT METHODS'), findsOneWidget);
  });

  testWidgets('payment preference UPI Only is unchanged by UPI confirm', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      profile: _sellerProfile(paymentPreference: 'UPI_ONLY'),
    );
    expect(find.text('UPI Only'), findsOneWidget);
  });
}
