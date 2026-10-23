import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/listing_discount.dart';
import 'package:societybites/screens/add_listing_screen.dart';

FoodItem _listing({
  String id = 'listing-1',
  double price = 200,
  bool discountEnabled = false,
  double? discountPercent,
  DateTime? discountStartsAt,
  DateTime? discountEndsAt,
  double? effectivePrice,
  bool discountActive = false,
  String? variantGroupId,
}) {
  return FoodItem(
    id: id,
    name: 'Samosa',
    sellerId: 's1',
    sellerName: 'Anita',
    block: 'A',
    price: price,
    discountEnabled: discountEnabled,
    discountPercent: discountPercent,
    discountStartsAt: discountStartsAt,
    discountEndsAt: discountEndsAt,
    effectivePrice: effectivePrice,
    discountActive: discountActive,
    variantGroupId: variantGroupId,
    rating: 5,
    pickupTime: '5 PM',
    description: '',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('listing discount helpers', () {
    test('missing JSON fields stay discount-disabled', () {
      final item = FoodItem.fromJson({
        'id': 'legacy-1',
        'name': 'Idli',
        'price': 80,
      });
      expect(item.price, 80);
      expect(item.discountEnabled, isFalse);
      expect(item.discountPercent, isNull);
      expect(item.discountStartsAt, isNull);
      expect(item.discountEndsAt, isNull);
      expect(item.effectivePrice, isNull);
      expect(item.discountActive, isFalse);
    });

    test('parses live discount fields without replacing price', () {
      final item = FoodItem.fromJson({
        'id': 'sale-1',
        'name': 'Idli',
        'price': 200,
        'discountEnabled': true,
        'discountPercent': 10,
        'discountActive': true,
        'effectivePrice': 180,
        'discountStartsAt': '2026-10-23T00:00:00.000Z',
        'discountEndsAt': '2026-10-24T18:29:59.999Z',
      });
      expect(item.price, 200);
      expect(item.discountEnabled, isTrue);
      expect(item.discountPercent, 10);
      expect(item.effectivePrice, 180);
      expect(item.discountActive, isTrue);
      expect(item.discountStartsAt, isNotNull);
      expect(item.discountEndsAt, isNotNull);
    });

    test('effective price uses backend money rounding', () {
      expect(listingDiscountEffectivePrice(200, 10), 180);
      expect(listingDiscountEffectivePrice(199, 10), 179.1);
      expect(listingDiscountEffectivePrice(200, 1), 198);
      expect(listingDiscountEffectivePrice(200, 90), 20);
    });

    test('accepts 1% and 90% and rejects 0 and 91', () {
      expect(
        listingDiscountValidationError(enabled: true, percent: 1),
        isNull,
      );
      expect(
        listingDiscountValidationError(enabled: true, percent: 90),
        isNull,
      );
      expect(
        listingDiscountValidationError(enabled: true, percent: 0),
        listingDiscountPercentRangeError,
      );
      expect(
        listingDiscountValidationError(enabled: true, percent: 91),
        listingDiscountPercentRangeError,
      );
      expect(
        listingDiscountValidationError(enabled: false, percent: 0),
        isNull,
      );
    });

    test('rejects an end date earlier than the start date', () {
      expect(
        listingDiscountValidationError(
          enabled: true,
          percent: 10,
          startsAt: DateTime(2026, 10, 23),
          endsAt: DateTime(2026, 10, 22),
        ),
        listingDiscountDateRangeError,
      );
      expect(
        listingDiscountValidationError(
          enabled: true,
          percent: 10,
          startsAt: DateTime(2026, 10, 23),
          endsAt: DateTime(2026, 10, 23),
        ),
        isNull,
      );
    });

    test('create/update API fields keep regular price out of the payload', () {
      final disabled = listingDiscountFieldsForApi(enabled: false);
      expect(disabled, {'discountEnabled': false});
      expect(disabled.containsKey('discountPercent'), isFalse);
      expect(disabled.containsKey('price'), isFalse);

      final enabled = listingDiscountFieldsForApi(
        enabled: true,
        percent: 10,
        startsAt: DateTime(2026, 10, 23),
        endsAt: DateTime(2026, 10, 24),
      );
      expect(enabled['discountEnabled'], isTrue);
      expect(enabled['discountPercent'], 10);
      expect(enabled['discountStartsAt'], isNotNull);
      expect(enabled['discountEndsAt'], isNotNull);
      expect(enabled.containsKey('price'), isFalse);
      expect(
        DateTime.parse(enabled['discountEndsAt'] as String).isBefore(
          DateTime.parse(enabled['discountStartsAt'] as String),
        ),
        isFalse,
      );
    });

    test('enabled write sends null dates when the seller leaves them blank', () {
      final fields = listingDiscountFieldsForApi(enabled: true, percent: 15);
      expect(fields['discountStartsAt'], isNull);
      expect(fields['discountEndsAt'], isNull);
    });
  });

  group('Add Listing discount UI', () {
    Future<void> pumpScreen(WidgetTester tester, {FoodItem? listing}) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: AddListingScreen(existingListing: listing)),
      );
      await tester.pump();
    }

    testWidgets('new listing is discount-disabled by default', (tester) async {
      await pumpScreen(tester);
      expect(find.text(listingDiscountToggleLabel), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('listing-discount-toggle')),
      );
      expect(toggle.value, isFalse);
      expect(find.byKey(const Key('listing-discount-percent')), findsNothing);
    });

    testWidgets('legacy listing without discount fields stays disabled', (
      tester,
    ) async {
      await pumpScreen(tester, listing: _listing());
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('listing-discount-toggle')),
      );
      expect(toggle.value, isFalse);
      expect(find.text('200'), findsWidgets);
      expect(find.byKey(const Key('listing-discount-percent')), findsNothing);
    });

    testWidgets('valid 10% preview uses regular price not effectivePrice', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(find.widgetWithText(TextFormField, '₹ 0.00'), '200');
      await tester.pump();
      await tester.tap(find.byKey(const Key('listing-discount-toggle')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('listing-discount-percent')),
        '10',
      );
      await tester.pump();
      expect(
        find.byKey(const Key('listing-discount-preview')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Regular price ₹200'),
        findsOneWidget,
      );
      expect(find.textContaining('Neighbors pay ₹180'), findsOneWidget);
    });

    testWidgets('loads an existing discount without replacing regular price', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        listing: _listing(
          price: 200,
          discountEnabled: true,
          discountPercent: 10,
          effectivePrice: 180,
          discountActive: true,
        ),
      );
      final priceField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, '₹ 0.00'),
      );
      expect(priceField.controller?.text, '200');
      expect(
        tester.widget<SwitchListTile>(
          find.byKey(const Key('listing-discount-toggle')),
        ).value,
        isTrue,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('listing-discount-percent')),
            )
            .controller
            ?.text,
        '10',
      );
    });

    testWidgets('disabling the toggle does not change the regular price', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        listing: _listing(
          price: 200,
          discountEnabled: true,
          discountPercent: 10,
          effectivePrice: 180,
        ),
      );
      await tester.tap(find.byKey(const Key('listing-discount-toggle')));
      await tester.pump();
      final priceField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, '₹ 0.00'),
      );
      expect(priceField.controller?.text, '200');
      expect(find.byKey(const Key('listing-discount-percent')), findsNothing);
    });

    testWidgets('form validator rejects 0% and 91%', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('listing-discount-toggle')));
      await tester.pump();

      final percent = find.byKey(const Key('listing-discount-percent'));
      await tester.ensureVisible(percent);
      await tester.enterText(percent, '0');
      await tester.pump();
      final form = tester.state<FormState>(find.byType(Form));
      expect(form.validate(), isFalse);
      await tester.pump();
      expect(find.textContaining('from 1 to 90'), findsWidgets);

      await tester.enterText(percent, '91');
      await tester.pump();
      expect(form.validate(), isFalse);
      await tester.pump();
      expect(find.textContaining('from 1 to 90'), findsWidgets);

      expect(listingDiscountValidationError(enabled: true, percent: 1), isNull);
      expect(listingDiscountValidationError(enabled: true, percent: 90), isNull);
    });

    testWidgets('variant group edit shows a shared-size warning', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        listing: _listing(
          discountEnabled: true,
          discountPercent: 10,
          variantGroupId: 'group-1',
        ),
      );
      expect(
        find.byKey(const Key('listing-discount-variant-note')),
        findsOneWidget,
      );
      expect(find.text(listingDiscountVariantGroupHint), findsOneWidget);
    });

    testWidgets('single-SKU edit does not show the variant-group warning', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        listing: _listing(discountEnabled: true, discountPercent: 10),
      );
      expect(
        find.byKey(const Key('listing-discount-variant-note')),
        findsNothing,
      );
    });
  });
}
