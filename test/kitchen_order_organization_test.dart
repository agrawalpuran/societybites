import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/kitchen_order_category.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('overflowed by') ||
        text.contains('Incorrect use of ParentDataWidget')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Map<String, dynamic> _listing({
  required String name,
  String availabilityMode = listingAvailabilityReadyNow,
  String catalogType = listingCatalogRegular,
}) {
  return {
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 80,
    'catalogType': catalogType,
    'availabilityMode': availabilityMode,
  };
}

Map<String, dynamic> _orderJson({
  required String id,
  required String name,
  String status = 'pending',
  String type = 'regular',
  String availabilityMode = listingAvailabilityReadyNow,
  String catalogType = listingCatalogRegular,
  String paymentStatus = 'pending',
}) {
  return {
    'id': id,
    'orderNumber': 'SB-$id',
    'status': status,
    'type': type,
    'paymentStatus': paymentStatus,
    'total': 80,
    'subtotal': 80,
    'communityFee': 0,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'items': [
      {
        'quantity': 1,
        'unitPrice': 80,
        'listing': _listing(
          name: name,
          availabilityMode: availabilityMode,
          catalogType: catalogType,
        ),
      },
    ],
  };
}

Map<String, dynamic> _mixedOrderJson() {
  return {
    'id': 'mixed-1',
    'orderNumber': 'SB-mixed',
    'status': 'pending',
    'type': 'regular',
    'total': 160,
    'subtotal': 160,
    'communityFee': 0,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'items': [
      {
        'quantity': 1,
        'unitPrice': 80,
        'listing': _listing(name: 'Dhokla'),
      },
      {
        'quantity': 1,
        'unitPrice': 80,
        'listing': _listing(
          name: 'Cake',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
      },
    ],
  };
}

Map<String, dynamic> _campaignJson() {
  return {
    'id': 'campaign-1',
    'title': 'Friday Specials',
    'status': 'open',
    'orderOpenAt': '2026-08-21T10:00:00.000Z',
    'orderCutoffAt': '2026-12-22T10:00:00.000Z',
    'fulfilmentAt': '2026-12-22T13:00:00.000Z',
  };
}

Future<void> _pumpKitchen(
  WidgetTester tester, {
  List<Map<String, dynamic>> orders = const [],
  List<Map<String, dynamic>> campaigns = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'user_id': 'seller-1',
    'user_role': 'seller',
    'user_name': 'Anita',
    'society_id': 'soc-1',
  });
  await tester.binding.setSurfaceSize(const Size(800, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SellerDashboardScreen(
        fetchOrders: () async => orders,
        fetchCampaigns: () async => campaigns,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_ignoreOverflow);

  test('classifies regular, made-to-order, pre-order, and mixed orders', () {
    final regular = Order.fromJson(_orderJson(id: 'r', name: 'Dhokla'));
    final mto = Order.fromJson(
      _orderJson(
        id: 'm',
        name: 'Cake',
        availabilityMode: listingAvailabilityMadeToOrder,
      ),
    );
    final preorder = Order.fromJson(
      _orderJson(id: 'p', name: 'Box', type: 'pre_order'),
    );
    final mixed = Order.fromJson(_mixedOrderJson());

    expect(kitchenCategoryForOrder(regular), KitchenOrderCategory.orders);
    expect(kitchenCategoryForOrder(mto), KitchenOrderCategory.madeToOrder);
    expect(kitchenCategoryForOrder(preorder), KitchenOrderCategory.preorders);
    expect(kitchenCategoryForOrder(mixed), KitchenOrderCategory.orders);
  });

  testWidgets('only regular orders hide the category selector', (tester) async {
    await _pumpKitchen(
      tester,
      orders: [_orderJson(id: '1', name: 'Dhokla')],
    );
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsNothing);
    expect(find.byKey(const ValueKey('kitchen-type-preorders')), findsNothing);
    expect(find.text('Dhokla'), findsWidgets);
    expect(find.text('Accept Order'), findsOneWidget);
    expect(find.text('No pre-order campaigns yet.'), findsNothing);
  });

  testWidgets('only made-to-order orders hide the category selector', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [
        _orderJson(
          id: '1',
          name: 'Cake',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
      ],
    );
    expect(find.byKey(const ValueKey('kitchen-type-madeToOrder')), findsNothing);
    expect(find.text('Cake'), findsWidgets);
    expect(find.text('Accept Order'), findsOneWidget);
  });

  testWidgets('only pre-orders hide the category selector', (tester) async {
    await _pumpKitchen(tester, campaigns: [_campaignJson()]);
    expect(find.byKey(const ValueKey('kitchen-type-preorders')), findsNothing);
    expect(find.text('Friday Specials'), findsOneWidget);
    expect(find.text('No active orders yet.'), findsNothing);
  });

  testWidgets('regular + closed campaigns shows the Pre-orders tab', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [_orderJson(id: '1', name: 'Dhokla')],
      campaigns: [
        {
          ..._campaignJson(),
          'status': 'closed',
        },
      ],
    );
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-type-preorders')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-type-madeToOrder')), findsNothing);
    expect(find.text('Dhokla'), findsWidgets);
    expect(find.text('Friday Specials'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('kitchen-type-preorders')));
    await tester.pump();
    expect(find.text('Friday Specials'), findsOneWidget);
    expect(find.text('Dhokla'), findsNothing);
  });

  testWidgets('regular + pre-order orders shows the selector', (tester) async {
    await _pumpKitchen(
      tester,
      orders: [
        _orderJson(id: '1', name: 'Dhokla'),
        _orderJson(id: 'p', name: 'Box', type: 'pre_order'),
      ],
    );
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-type-preorders')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-type-madeToOrder')), findsNothing);
    expect(find.text('Dhokla'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('kitchen-type-preorders')));
    await tester.pump();
    expect(find.text('Box'), findsWidgets);
    expect(find.text('Dhokla'), findsNothing);
  });

  testWidgets('regular + made-to-order + pre-orders shows three options', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [
        _orderJson(id: '1', name: 'Dhokla'),
        _orderJson(
          id: '2',
          name: 'Cake',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
        _orderJson(id: 'p', name: 'Box', type: 'pre_order'),
      ],
    );
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-type-madeToOrder')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-type-preorders')), findsOneWidget);
    expect(find.text('Dhokla'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('kitchen-type-madeToOrder')));
    await tester.pump();
    expect(find.text('Cake'), findsWidgets);
    expect(find.text('Dhokla'), findsNothing);
    expect(find.text('Accept Order'), findsOneWidget);
  });

  testWidgets('no orders shows a clean empty state without type tabs', (
    tester,
  ) async {
    await _pumpKitchen(tester);
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsNothing);
    expect(find.textContaining('No active orders yet.'), findsOneWidget);
    expect(find.text('No pre-order campaigns yet.'), findsNothing);
    expect(find.byKey(const Key('my-kitchen-add-listing')), findsOneWidget);
    expect(find.byKey(const Key('my-kitchen-listings')), findsOneWidget);
    expect(find.text('Add listing'), findsOneWidget);
    expect(find.text('My Listings'), findsWidgets);
  });

  testWidgets('switching types does not hide Active/Past or messages', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [
        _orderJson(id: '1', name: 'Dhokla', status: 'completed'),
        _orderJson(
          id: '2',
          name: 'Cake',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
      ],
    );
    expect(find.textContaining('Active'), findsOneWidget);
    expect(find.textContaining('Past'), findsOneWidget);
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('Dhokla'), findsWidgets);
  });

  testWidgets('past-only made-to-order keeps a tab that reaches it', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [
        _orderJson(id: '1', name: 'Dhokla'),
        _orderJson(
          id: '2',
          name: 'Cake',
          status: 'completed',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
      ],
    );
    expect(
      find.byKey(const ValueKey('kitchen-type-madeToOrder')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('kitchen-type-madeToOrder')));
    await tester.pump();
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('Cake'), findsWidgets);
  });

  testWidgets('a just-rejected order keeps the Orders tab and stays in Active', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [
        {
          ..._orderJson(id: '1', name: 'Dry Fruits', status: 'rejected'),
          'rejectedAt': DateTime.now().toUtc().toIso8601String(),
        },
        _orderJson(
          id: '2',
          name: 'Cake',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
      ],
    );
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kitchen-type-orders')));
    await tester.pump();
    expect(find.text('Dry Fruits'), findsWidgets);
  });

  testWidgets('a rejection older than the grace period sits in Past', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [
        {
          ..._orderJson(id: '1', name: 'Dry Fruits', status: 'rejected'),
          'rejectedAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        },
        _orderJson(
          id: '2',
          name: 'Cake',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
      ],
    );
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kitchen-type-orders')));
    await tester.pump();
    expect(find.text('Dry Fruits'), findsNothing);
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('Dry Fruits'), findsWidgets);
  });

  testWidgets('action badges appear on kitchen type and Active tabs', (
    tester,
  ) async {
    await _pumpKitchen(
      tester,
      orders: [
        _orderJson(id: '1', name: 'Dhokla', status: 'pending'),
        _orderJson(
          id: '2',
          name: 'Cake',
          status: 'pending',
          availabilityMode: listingAvailabilityMadeToOrder,
        ),
        _orderJson(
          id: '3',
          name: 'Samosa',
          status: 'accepted',
          paymentStatus: 'pending',
        ),
      ],
    );
    expect(find.byKey(const ValueKey('kitchen-type-orders')), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-type-madeToOrder')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('kitchen-type-badge-orders')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('kitchen-type-badge-madeToOrder')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kitchen-active-badge')), findsOneWidget);
  });
}
