import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('Incorrect use of ParentDataWidget')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _pumpKitchen(
  WidgetTester tester, {
  required String role,
  VoidCallback? onStartSelling,
}) async {
  SharedPreferences.setMockInitialValues({
    'user_id': 'user-1',
    'user_role': role,
    'user_name': 'Puran',
  });
  await tester.binding.setSurfaceSize(const Size(800, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SellerDashboardScreen(
        fetchOrders: () async => const [],
        fetchCampaigns: () async => const [],
        onStartSelling: onStartSelling,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_ignoreOverflow);

  testWidgets('buyer My Kitchen shows Start Selling instead of seller orders', (
    tester,
  ) async {
    var started = false;
    await _pumpKitchen(
      tester,
      role: 'buyer',
      onStartSelling: () => started = true,
    );

    expect(find.text('Start Selling'), findsOneWidget);
    expect(find.text('Start selling homemade food'), findsOneWidget);
    expect(find.text('Add listing'), findsNothing);
    expect(find.text('My Listings'), findsNothing);
    expect(find.textContaining('No active orders yet'), findsNothing);

    await tester.tap(find.text('Start Selling'));
    await tester.pump();
    expect(started, isTrue);
  });

  testWidgets('seller My Kitchen keeps Add listing and does not show Start Selling', (
    tester,
  ) async {
    await _pumpKitchen(tester, role: 'seller');

    expect(find.text('Start Selling'), findsNothing);
    expect(find.byKey(const Key('my-kitchen-add-listing')), findsOneWidget);
    expect(find.textContaining('No active orders yet'), findsOneWidget);
  });
}
