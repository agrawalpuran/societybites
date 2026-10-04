import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/models/recurring_availability.dart';
import 'package:societybites/screens/add_listing_screen.dart';
import 'package:societybites/screens/my_listings_screen.dart';
import 'package:societybites/widgets/listing_purchase_slot.dart';
import 'package:societybites/widgets/recurring_availability_hint.dart';

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

Map<String, dynamic> _listingJson({
  String name = 'Idli',
  String availabilityMode = 'READY_NOW',
  String catalogType = 'REGULAR',
  bool recurring = false,
  bool unavailable = false,
}) {
  return {
    'id': 'listing-1',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 60,
    'quantity': 99,
    'status': 'active',
    'catalogType': catalogType,
    'availabilityMode': availabilityMode,
    'recurringEnabled': recurring,
    'recurringWeekdays': recurring ? [1, 2, 3, 4, 5, 6] : [],
    'recurringStartMinute': recurring ? 420 : null,
    'recurringEndMinute': recurring ? 660 : null,
    'recurringDailyLimit': recurring ? 20 : null,
    'recurringUnavailable': unavailable,
    'recurringBuyerLabel': recurring
        ? (unavailable
            ? 'Not available now'
            : 'Available today · Until 11:00 AM')
        : '',
    'recurringNextLabel': unavailable ? 'Available tomorrow from 7:00 AM' : '',
    'recurringScheduleSummary': recurring ? 'Mon–Sat' : '',
    'recurringHoursSummary': recurring ? '7:00 AM – 11:00 AM' : '',
    'recurringDailyLimitLabel': recurring ? '20/day' : '',
    'preparationTimeMinutes': availabilityMode == 'MADE_TO_ORDER' ? 60 : null,
    'categories': ['Breakfast'],
    'foodType': 'VEG',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_name': 'Anita',
      'phone': '9999999999',
    });
  });

  test('unscheduled ready-now listing stays orderable', () {
    final food = FoodItem.fromJson(_listingJson());
    expect(food.isRecurringReadyNow, isFalse);
    expect(food.canAddToCart, isTrue);
  });

  test('recurring listing outside schedule is visible but not orderable', () {
    final food = FoodItem.fromJson(_listingJson(recurring: true, unavailable: true));
    expect(food.isRecurringReadyNow, isTrue);
    expect(food.canAddToCart, isFalse);
    expect(food.recurringWindowLabel, 'Mon–Sat · 7:00 AM – 11:00 AM');
  });

  test('weekday range summary uses Mon–Fri when consecutive', () {
    expect(
      formatRecurringWeekdaysSummary([1, 2, 3, 4, 5]),
      'Mon–Fri',
    );
  });

  testWidgets('Available Now form shows today only and repeat schedule', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: AddListingScreen(
          initialAvailabilityMode: listingAvailabilityReadyNow,
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Just today'));
    expect(find.text('Just today'), findsOneWidget);
    expect(find.text('Same days every week'), findsOneWidget);
    expect(find.text('QUANTITY AVAILABLE'), findsOneWidget);
    expect(find.text('DATE/TIME AVAILABLE UNTIL'), findsNothing);
    expect(find.text('AVAILABLE UNTIL (OPTIONAL)'), findsNothing);
    expect(find.text('Full day'), findsOneWidget);
    expect(find.text('Specific hours'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Full day')).dy,
      lessThan(tester.getTopLeft(find.text('Same days every week')).dy),
    );

    await tester.tap(find.byKey(const Key('listing-today-hours')));
    await tester.pump();
    expect(find.byKey(const Key('listing-today-start')), findsOneWidget);
    expect(find.text('AVAILABLE UNTIL (OPTIONAL)'), findsNothing);

    expect(find.text('Till stock lasts'), findsOneWidget);
    await tester.tap(find.byKey(const Key('listing-availability-until-stock')));
    await tester.pump();
    expect(find.text('Full day'), findsNothing);
    expect(find.text('WHICH DAYS?'), findsNothing);
    expect(find.text('QUANTITY AVAILABLE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('listing-availability-repeat')));
    await tester.pump();
    expect(find.text('WHICH DAYS?'), findsOneWidget);
    expect(find.text('WHAT TIME?'), findsOneWidget);
    expect(find.text('No limit'), findsOneWidget);
    expect(find.text('I have a limit'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('No limit')).dy,
      tester.getTopLeft(find.text('I have a limit')).dy,
    );
    expect(find.text('QUANTITY AVAILABLE'), findsNothing);
    expect(find.text('AVAILABLE UNTIL (OPTIONAL)'), findsNothing);

    await tester.tap(find.byKey(const Key('listing-recurring-day-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('listing-daily-limit')));
    await tester.pump();
    expect(find.byKey(const Key('listing-daily-limit-field')), findsOneWidget);
  });

  testWidgets('Made to Order form does not show recurring schedule', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: AddListingScreen(
          initialAvailabilityMode: listingAvailabilityMadeToOrder,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Today only'), findsNothing);
    expect(find.text('Just today'), findsNothing);
    expect(find.text('Repeat schedule'), findsNothing);
    expect(find.text('Same days every week'), findsNothing);
    expect(find.text('PREPARATION TIME'), findsOneWidget);
  });

  testWidgets('Pre-order catalog form does not show recurring schedule', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: AddListingScreen(catalogType: listingCatalogPreorder),
      ),
    );
    await tester.pump();
    expect(find.text('Today only'), findsNothing);
    expect(find.text('Just today'), findsNothing);
    expect(find.text('Repeat schedule'), findsNothing);
    expect(find.text('Same days every week'), findsNothing);
  });

  testWidgets('My Listings shows a compact schedule summary', (tester) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [
            _listingJson(recurring: true, unavailable: true),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Idli'), findsOneWidget);
    expect(find.textContaining('Mon–Sat'), findsOneWidget);
    expect(find.textContaining('7:00 AM – 11:00 AM'), findsOneWidget);
    expect(find.textContaining('20/day'), findsOneWidget);
    expect(find.text('NOT LIVE YET'), findsOneWidget);
    expect(find.text('Available tomorrow from 7:00 AM'), findsOneWidget);
  });

  testWidgets('buyer sees friendly recurring availability copy', (tester) async {
    _ignoreOverflow();
    final available = FoodItem.fromJson(_listingJson(recurring: true));
    final closed = FoodItem.fromJson(
      _listingJson(recurring: true, unavailable: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RecurringAvailabilityHint(food: available),
              RecurringAvailabilityHint(food: closed),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Available today · Until 11:00 AM'), findsOneWidget);
    expect(find.text('Not available now'), findsOneWidget);
    expect(find.text('Mon–Sat · 7:00 AM – 11:00 AM'), findsWidgets);
    expect(find.text('Available tomorrow from 7:00 AM'), findsOneWidget);
    expect(find.text('Temporarily not available'), findsNothing);
    expect(find.text('recurringEnabled'), findsNothing);
  });

  testWidgets('compact buyer card shows schedule without overflowing', (
    tester,
  ) async {
    _ignoreOverflow();
    final closed = FoodItem.fromJson(
      _listingJson(recurring: true, unavailable: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 160,
            child: RecurringAvailabilityHint(food: closed, compact: true),
          ),
        ),
      ),
    );
    expect(find.text('Not available now'), findsOneWidget);
    expect(find.text('Mon–Sat · 7:00 AM – 11:00 AM'), findsOneWidget);
    expect(find.text('Available tomorrow from 7:00 AM'), findsNothing);
  });

  testWidgets('purchase slot does not repeat not available now', (tester) async {
    final closed = FoodItem.fromJson(
      _listingJson(recurring: true, unavailable: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RecurringAvailabilityHint(food: closed, compact: true),
              MarketplacePurchaseSlot(
                food: closed,
                cartQty: 0,
                compact: true,
                soldOut: const Text('Sold out'),
                addButton: const Text('Add'),
                qtyStepper: const Text('qty'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Not available now'), findsOneWidget);
    expect(find.text('Add'), findsNothing);
  });
}
