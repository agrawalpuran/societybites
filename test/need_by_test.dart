import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/screens/checkout_screen.dart';
import 'package:societybites/screens/orders_screen.dart';
import 'package:societybites/screens/preorder_checkout_screen.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/widgets/requested_ready_summary.dart';

Map<String, dynamic> _listingJson({
  required String name,
  String availabilityMode = listingAvailabilityReadyNow,
  int? preparationTimeMinutes,
  String catalogType = 'REGULAR',
}) {
  return {
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 100,
    'status': 'active',
    'catalogType': catalogType,
    'availabilityMode': availabilityMode,
    'preparationTimeMinutes': preparationTimeMinutes,
    'foodType': 'VEG',
    'category': 'Desserts',
    'quantity': 5,
  };
}

FoodItem _mtoFood() => FoodItem.fromJson(
      _listingJson(
        name: 'Chocolate Cake',
        availabilityMode: listingAvailabilityMadeToOrder,
        preparationTimeMinutes: 2880,
      ),
    );

Map<String, dynamic> _orderJson({
  String status = 'pending',
  String? requestedReadyAt,
  String? expectedReadyAt,
  String paymentMethod = 'cash',
  String paymentStatus = 'pending',
  bool madeToOrder = true,
}) {
  return {
    'id': 'need-by-1',
    'orderNumber': 'SB-need-by-1',
    'status': status,
    'statusStep': BuyerOrderLifecycle.progressStep(status),
    'paymentStatus': paymentStatus,
    'paymentMethod': paymentMethod,
    'total': 120,
    'subtotal': 115,
    'communityFee': 5,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'requestedReadyAt': requestedReadyAt,
    'expectedReadyAt': expectedReadyAt,
    'items': [
      {
        'quantity': 1,
        'unitPrice': 115,
        'listing': madeToOrder
            ? _listingJson(
                name: 'Chocolate Cake',
                availabilityMode: listingAvailabilityMadeToOrder,
                preparationTimeMinutes: 2880,
              )
            : _listingJson(name: 'Samosa'),
      },
    ],
  };
}

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed')) return;
    previous?.call(details);
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'society_id': 'society-a',
      'user_name': 'Neighbor',
    });
  });

  test('requestedReadyAt is independent of expectedReadyAt', () {
    final requested = DateTime.now().add(const Duration(hours: 20));
    final expected = DateTime.now().add(const Duration(hours: 18));
    final order = Order.fromJson(
      _orderJson(
        status: 'accepted',
        requestedReadyAt: requested.toUtc().toIso8601String(),
        expectedReadyAt: expected.toUtc().toIso8601String(),
      ),
    );
    expect(order.requestedReadyAt, isNotNull);
    expect(order.expectedReadyAt, isNotNull);
    expect(order.requestedReadyAt!.isAfter(order.expectedReadyAt!), isTrue);
    expect(order.requestedEarlierThanUsualLead, isTrue);
    expect(order.usualLeadTimeLabel, '2 days');
  });

  testWidgets('Need-by field is visible only for Made-to-Order checkout', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [CartItem(food: _mtoFood(), quantity: 1)],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('When do you need it?'), findsOneWidget);
    expect(find.text('No specific date'), findsOneWidget);
    expect(find.text('I need it by'), findsOneWidget);
    expect(
      find.text('Seller will confirm whether this date is possible.'),
      findsOneWidget,
    );
  });

  testWidgets('Need-by field is hidden for Available Now checkout', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [
            CartItem(
              food: FoodItem.fromJson(_listingJson(name: 'Samosa')),
              quantity: 1,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('When do you need it?'), findsNothing);
    expect(find.byType(NeedByCheckoutField), findsNothing);
  });

  testWidgets('Need-by field is not added to pre-order checkout', (tester) async {
    final now = DateTime.now();
    const product = PreOrderProduct(
      listingId: 'listing-1',
      name: 'Thali',
      sellerId: 'seller-1',
      sellerName: 'Anita',
      price: 150,
      inventoryMode: 'demand',
      quantity: 0,
    );
    final campaign = PreOrderCampaign(
      id: 'c1',
      sellerId: 'seller-1',
      title: 'Weekend Thali',
      status: 'open',
      orderOpenAt: now.subtract(const Duration(hours: 1)),
      orderCutoffAt: now.add(const Duration(days: 2)),
      fulfilmentAt: now.add(const Duration(days: 3)),
      products: const [product],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PreOrderCheckoutScreen(
          campaign: campaign,
          selectedItems: const {product: 1},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('When do you need it?'), findsNothing);
  });

  testWidgets('optional Need-by stays null when No specific date is selected', (
    tester,
  ) async {
    _ignoreOverflow();
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DateTime? sentNeedBy;
    var placed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [CartItem(food: _mtoFood(), quantity: 1)],
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
            requestedReadyAt,
          }) async {
            placed = true;
            sentNeedBy = requestedReadyAt;
            return {'id': 'o1'};
          },
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('confirm-order')));
    await tester.tap(find.byKey(const Key('confirm-order')));
    await tester.pump();
    await tester.pump();
    expect(placed, isTrue);
    expect(sentNeedBy, isNull);
  });

  testWidgets('buyer sees Need by and seller-confirmed ready time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requested = DateTime.now().add(const Duration(hours: 20));
    final expected = DateTime.now().add(const Duration(hours: 18));
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [
            _orderJson(
              status: 'accepted',
              requestedReadyAt: requested.toUtc().toIso8601String(),
              expectedReadyAt: expected.toUtc().toIso8601String(),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Need by'), findsOneWidget);
    expect(find.textContaining('Seller confirmed ready by'), findsOneWidget);
  });

  testWidgets('seller sees requested date and earlier-than-lead warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final requested = DateTime.now().add(const Duration(hours: 20));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerActiveOrderCard(
            order: Order.fromJson(
              _orderJson(
                requestedReadyAt: requested.toUtc().toIso8601String(),
              ),
            ),
            onAction: (_, _) async {},
            onOrderUpdated: (_) {},
            onPaymentConfirmed: () async {},
            onReject: (_) async {},
            onReadyBy: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Buyer requested by'), findsOneWidget);
    expect(find.textContaining('Your usual lead time: 2 days'), findsOneWidget);
    expect(find.byKey(const Key('earlier-than-lead-warning')), findsOneWidget);
  });

  testWidgets('accept confirmation dialog appears only when earlier than lead', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var accepted = false;
    final requested = DateTime.now().add(const Duration(hours: 20));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerActiveOrderCard(
            order: Order.fromJson(
              _orderJson(
                requestedReadyAt: requested.toUtc().toIso8601String(),
              ),
            ),
            onAction: (_, status) async {
              if (status == 'accepted') accepted = true;
            },
            onOrderUpdated: (_) {},
            onPaymentConfirmed: () async {},
            onReject: (_) async {},
            onReadyBy: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Accept Order'));
    await tester.pumpAndSettle();
    expect(find.text('Earlier than your usual lead time'), findsOneWidget);
    expect(accepted, isFalse);
    await tester.tap(find.byKey(const Key('accept-confirm-early-need-by')));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('normal accept flow is unchanged without Need by', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerActiveOrderCard(
            order: Order.fromJson(_orderJson()),
            onAction: (_, status) async {
              if (status == 'accepted') accepted = true;
            },
            onOrderUpdated: (_) {},
            onPaymentConfirmed: () async {},
            onReject: (_) async {},
            onReadyBy: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Accept Order'));
    await tester.pumpAndSettle();
    expect(find.text('Earlier than your usual lead time'), findsNothing);
    expect(accepted, isTrue);
    expect(find.text('Reject'), findsOneWidget);
  });

  test('existing reject reason is still available', () {
    expect(
      BuyerOrderVisibility.rejectReasons,
      contains('Unable to fulfil by requested date'),
    );
    expect(BuyerOrderVisibility.rejectReasons, contains('Not enough time'));
  });
}
