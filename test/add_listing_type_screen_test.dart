import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/add_listing_screen.dart';
import 'package:societybites/screens/add_listing_type_screen.dart';
import 'package:societybites/screens/create_preorder_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('listing type illustrations are bundled as assets', () async {
    for (final path in const [
      'assets/images/available_now.jpg',
      'assets/images/made_to_order.jpg',
      'assets/images/pre_order.jpg',
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });

  Future<void> pumpTypeScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: AddListingTypeScreen()),
    );
    await tester.pump();
  }

  testWidgets('Add Listing entry shows three order types', (tester) async {
    await pumpTypeScreen(tester);

    expect(find.text('Add Listing'), findsOneWidget);
    expect(find.text('What type of order is this?'), findsOneWidget);
    expect(find.text('Available Now'), findsWidgets);
    expect(find.text('Made to Order'), findsWidgets);
    expect(find.text('Pre-Order'), findsWidgets);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Not sure which to choose?'), findsOneWidget);
  });

  testWidgets('Available Now continue opens existing listing form', (
    tester,
  ) async {
    await pumpTypeScreen(tester);

    await tester.tap(find.byKey(const Key('listing-type-available-now')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing-type-continue')));
    await tester.pumpAndSettle();

    expect(find.byType(AddListingScreen), findsOneWidget);
    expect(find.text('Available now order'), findsOneWidget);
    expect(find.text('HOW WILL YOU FULFIL THIS?'), findsNothing);
    expect(find.text('PREPARATION TIME'), findsNothing);
  });

  testWidgets('Made to Order continue opens listing form with MTO selected', (
    tester,
  ) async {
    await pumpTypeScreen(tester);

    await tester.tap(find.byKey(const Key('listing-type-made-to-order')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing-type-continue')));
    await tester.pumpAndSettle();

    expect(find.byType(AddListingScreen), findsOneWidget);
    expect(find.text('Made to order'), findsOneWidget);
    expect(find.text('HOW WILL YOU FULFIL THIS?'), findsNothing);
    expect(find.text('PREPARATION TIME'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
  });

  testWidgets('Pre-Order continue opens existing campaign flow', (tester) async {
    await pumpTypeScreen(tester);

    await tester.tap(find.byKey(const Key('listing-type-pre-order')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing-type-continue')));
    await tester.pumpAndSettle();

    expect(find.byType(CreatePreOrderScreen), findsOneWidget);
    expect(find.text('Pre-order'), findsOneWidget);
    expect(find.byType(AddListingScreen), findsNothing);
  });

  testWidgets('editing an existing listing skips the type screen', (
    tester,
  ) async {
    final listing = FoodItem(
      id: 'l1',
      name: 'Samosa',
      sellerId: 's1',
      sellerName: 'Anita',
      block: 'A',
      price: 25,
      rating: 5,
      pickupTime: '5 PM',
      description: '',
      icon: Icons.restaurant,
      bgColor: const Color(0xFFE8F5EE),
    );

    await tester.pumpWidget(
      MaterialApp(home: AddListingScreen(existingListing: listing)),
    );
    await tester.pump();

    expect(find.byType(AddListingTypeScreen), findsNothing);
    expect(find.text('Available now order'), findsOneWidget);
    expect(find.text('What type of order is this?'), findsNothing);
  });
}
