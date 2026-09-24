import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/screens/add_listing_screen.dart';
import 'package:societybites/screens/create_preorder_screen.dart';
import 'package:societybites/widgets/required_field_label.dart';

void main() {
  testWidgets('Add Listing shows required legend and asterisks on mandatory fields',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AddListingScreen()));
    await tester.pump();

    expect(find.byType(RequiredFieldsLegend), findsOneWidget);
    expect(find.text('ITEM NAME'), findsOneWidget);
    expect(find.text('Available now order'), findsOneWidget);
    expect(find.text('PRICE PER PORTION'), findsOneWidget);
    expect(find.text('QUANTITY AVAILABLE'), findsOneWidget);
    expect(find.text('AVAILABLE IN'), findsOneWidget);
    expect(find.text('FOOD TYPE'), findsOneWidget);
    expect(find.text('HOW WILL YOU FULFIL THIS?'), findsNothing);
    expect(find.text('DESCRIPTION & INGREDIENTS'), findsOneWidget);
    expect(find.text('FOOD TAGS'), findsOneWidget);
    expect(find.text('WEIGHT PER PORTION'), findsOneWidget);
    expect(find.text('PREPARATION TIME'), findsNothing);

    final requiredLabels = tester
        .widgetList<RequiredFieldLabel>(find.byType(RequiredFieldLabel))
        .where((label) => label.required)
        .map((label) => label.label)
        .toSet();
    expect(
      requiredLabels,
      containsAll([
        'ITEM NAME',
        'PRICE PER PORTION',
        'QUANTITY AVAILABLE',
        'AVAILABLE IN',
        'FOOD TYPE',
      ]),
    );
    expect(requiredLabels, isNot(contains('DESCRIPTION & INGREDIENTS')));
    expect(requiredLabels, isNot(contains('FOOD TAGS')));
    expect(requiredLabels, isNot(contains('WEIGHT PER PORTION')));
    expect(requiredLabels, isNot(contains('DATE/TIME AVAILABLE UNTIL')));
  });

  testWidgets('Made to Order adds a required preparation-time indicator', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: AddListingScreen(
          initialAvailabilityMode: listingAvailabilityMadeToOrder,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('HOW WILL YOU FULFIL THIS?'), findsNothing);
    expect(find.text('Made to order'), findsOneWidget);
    expect(find.text('PREPARATION TIME'), findsOneWidget);
    final prep = tester
        .widgetList<RequiredFieldLabel>(find.byType(RequiredFieldLabel))
        .firstWhere((label) => label.label == 'PREPARATION TIME');
    expect(prep.required, isTrue);
    expect(find.text('QUANTITY AVAILABLE'), findsNothing);
    expect(find.text('MAXIMUM ORDERS PER DAY (OPTIONAL)'), findsNothing);
  });

  testWidgets('Create pre-order marks campaign dates and title required', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CreatePreOrderScreen()));
    await tester.pump();

    expect(find.byType(RequiredFieldsLegend), findsOneWidget);
    final requiredLabels = tester
        .widgetList<RequiredFieldLabel>(find.byType(RequiredFieldLabel))
        .where((label) => label.required)
        .map((label) => label.label)
        .toSet();
    expect(
      requiredLabels,
      containsAll([
        'CAMPAIGN TITLE',
        'ORDER OPENS',
        'ORDER CUTOFF',
        'DELIVERY DATE & TIME',
        'FULFILMENT METHOD',
      ]),
    );
    expect(requiredLabels, isNot(contains('DESCRIPTION (OPTIONAL)')));
  });
}
