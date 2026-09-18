import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/models/seller_payment_preference.dart';
import 'package:societybites/screens/checkout_screen.dart';
import 'package:societybites/screens/orders_screen.dart';
import 'package:societybites/screens/payment_screen.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/widgets/order_fulfilment_banner.dart';

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

FoodItem _food({String preference = 'UPI_AND_COD'}) {
  return FoodItem.fromJson({
    'id': 'listing-1',
    'name': 'Paneer',
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 80,
    'quantity': 4,
    'status': 'active',
    'sellerPaymentPreference': preference,
  });
}

Map<String, dynamic> _orderJson({
  required String status,
  String paymentMethod = 'upi',
  String paymentStatus = 'pending',
  String? fulfilmentMethod,
}) {
  return {
    'id': 'o1',
    'orderNumber': 'SB-o1',
    'status': status,
    'statusStep': BuyerOrderLifecycle.progressStep(status),
    'paymentStatus': paymentStatus,
    'paymentMethod': paymentMethod,
    'total': 120,
    'subtotal': 115,
    'communityFee': 5,
    'fulfilmentMethod': fulfilmentMethod,
    'deliveryCharge': fulfilmentMethod == 'seller_delivery' ? 30 : 0,
    'createdAt': '2026-09-18T10:00:00.000Z',
    'items': [
      {
        'quantity': 1,
        'unitPrice': 115,
        'listing': {
          'id': 'listing-1',
          'name': 'Paneer',
          'sellerId': 'seller-1',
          'sellerName': 'Anita',
          'price': 115,
        },
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _ignoreOverflow();
  });

  test('UPI_ONLY hides COD, UPI_AND_COD allows it', () {
    expect(parseSellerPaymentPreference('UPI_ONLY').allowsCod, isFalse);
    expect(parseSellerPaymentPreference(null).allowsCod, isTrue);
    expect(parseSellerPaymentPreference('UPI_AND_COD').allowsCod, isTrue);
  });

  test('UPI pending blocks mark ready and time; COD does not', () {
    final pending = SellerPaymentActions.fromOrder(
      status: 'accepted',
      paymentMethod: 'upi',
      paymentStatus: 'pending',
    );
    expect(pending.showPaymentPending, isTrue);
    expect(pending.showMarkReady, isFalse);
    expect(pending.canSetReadyBy, isFalse);
    expect(pending.showConfirmOrderAndChooseTime, isFalse);
    expect(pending.promptReadyByOnAccept, isFalse);

    final marked = SellerPaymentActions.fromOrder(
      status: 'accepted',
      paymentMethod: 'upi',
      paymentStatus: 'buyer_marked_paid',
    );
    expect(marked.showPaymentPending, isTrue);
    expect(marked.showConfirmOrderAndChooseTime, isTrue);
    expect(marked.showMarkReady, isFalse);
    expect(marked.canSetReadyBy, isFalse);

    final confirmed = SellerPaymentActions.fromOrder(
      status: 'accepted',
      paymentMethod: 'upi',
      paymentStatus: 'seller_confirmed',
    );
    expect(confirmed.showPaymentPending, isFalse);
    expect(confirmed.showMarkReady, isTrue);
    expect(confirmed.canSetReadyBy, isTrue);
    expect(confirmed.showConfirmOrderAndChooseTime, isFalse);

    final cash = SellerPaymentActions.fromOrder(
      status: 'accepted',
      paymentMethod: 'cash',
      paymentStatus: 'pending',
    );
    expect(cash.showPaymentPending, isFalse);
    expect(cash.showMarkReady, isTrue);
    expect(cash.canSetReadyBy, isTrue);
    expect(cash.promptReadyByOnAccept, isTrue);
    expect(cash.showConfirmOrderAndChooseTime, isFalse);
  });

  testWidgets('seller profile can change payment preference', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
      'phone': '+919901844776',
    });
    var saved = 'UPI_AND_COD';
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          fetchProfile: () async => {
            'id': 'seller-1',
            'name': 'Anita',
            'phone': '+919901844776',
            'role': 'seller',
            'paymentPreference': saved,
            'sellingReachLevel': 'MY_SOCIETY',
            'sellingReach': {
              'cityKey': 'bengaluru',
              'nearbyRadiusKm': 5,
              'extendedRadiusKm': 10,
            },
            'fulfilmentMode': 'BUYER_PICKUP',
            'society': {'name': 'Prestige Notting Hill'},
            'flat': {'flatNumber': '3062'},
          },
          updateProfile: ({
            sellingReachLevel,
            fulfilmentMode,
            deliveryCharge,
            paymentPreference,
          }) async {
            saved = paymentPreference ?? saved;
            return {
              'id': 'seller-1',
              'role': 'seller',
              'paymentPreference': saved,
              'sellingReachLevel': 'MY_SOCIETY',
              'fulfilmentMode': 'BUYER_PICKUP',
            };
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    expect(find.text('PAYMENT METHODS'), findsOneWidget);
    expect(find.text('UPI + Cash on Delivery'), findsOneWidget);

    await tester.ensureVisible(find.text('Change').at(1));
    await tester.tap(find.text('Change').at(1));
    await tester.pumpAndSettle();
    expect(find.text('UPI Only'), findsWidgets);
    expect(find.text('Buyers must pay through UPI.'), findsWidgets);
    await tester.tap(find.text('UPI Only').last);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, 'UPI_ONLY');
  });

  testWidgets('UPI-only checkout hides COD', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'society_id': 'society-a',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [CartItem(food: _food(preference: 'UPI_ONLY'), quantity: 1)],
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async =>
              {'id': 'o1'},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Cash on Delivery'), findsNothing);
    expect(find.byKey(const Key('payment-cash')), findsNothing);
  });

  testWidgets('UPI + COD checkout can select COD', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'society_id': 'society-a',
    });
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(
          cartItems: [CartItem(food: _food(), quantity: 1)],
          placeOrder: ({
            required societyId,
            required items,
            required paymentMethod,
            fulfilmentMethod,
          }) async {
            sent = paymentMethod;
            return {'id': 'o1'};
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('UPI'), findsOneWidget);
    expect(find.text('Cash on Delivery'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment-cash')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('confirm-order')));
    await tester.tap(find.byKey(const Key('confirm-order')));
    await tester.pump();
    await tester.pump();
    expect(sent, 'cash');
  });

  testWidgets('existing I Have Paid remains on UPI payment screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentScreen(
          order: Order.fromJson(_orderJson(status: 'accepted')),
          fetchPaymentInfo: (_) async => {
            'sellerUpiId': 'anita@upi',
            'paymentStatus': 'pending',
            'paymentMethod': 'upi',
          },
          markPaid: (_) async => _orderJson(
            status: 'accepted',
            paymentStatus: 'buyer_marked_paid',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text("I've Paid via UPI"), findsOneWidget);
  });

  testWidgets('buyer order status still follows existing copy', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [
            _orderJson(status: 'accepted', paymentStatus: 'pending'),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Order confirmed'), findsOneWidget);
    expect(find.text('Your order is being prepared.'), findsOneWidget);
  });

  testWidgets('fulfilment banner is unchanged on COD delivery orders', (tester) async {
    final order = Order.fromJson(
      _orderJson(
        status: 'accepted',
        paymentMethod: 'cash',
        fulfilmentMethod: 'seller_delivery',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderFulfilmentBanner(order: order, isSellerView: true),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Delivery'), findsWidgets);
  });
}
