import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/screens/order_conversation_screen.dart';
import 'package:societybites/screens/orders_screen.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/widgets/order_messages_button.dart';

Map<String, dynamic> _orderJson({
  String status = 'accepted',
  int unread = 0,
}) {
  return {
    'id': 'o1',
    'orderNumber': 'SB-545661',
    'status': status,
    'statusStep': BuyerOrderLifecycle.progressStep(status),
    'paymentStatus': 'pending',
    'paymentMethod': 'upi',
    'buyerName': 'Puran',
    'total': 120,
    'subtotal': 115,
    'communityFee': 5,
    'unreadMessageCount': unread,
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
          'imageUrl': 'https://example.com/paneer.jpg',
        },
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Test Neighbor',
      'flat_number': '101',
    });
  });

  Future<void> setTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Message Seller appears on buyer order', (tester) async {
    await setTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: OrdersScreen(
          fetchOrders: ({required String role}) async => [_orderJson()],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Message Seller'), findsOneWidget);
    expect(find.byKey(const Key('order-messages-button')), findsOneWidget);
  });

  testWidgets('Message Buyer appears on seller order', (tester) async {
    await setTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SellerActiveOrderCard(
              order: Order.fromJson(_orderJson()),
              onAction: (_, _) async {},
              onOrderUpdated: (_) {},
              onPaymentConfirmed: () async {},
              onReject: (_) async {},
              onReadyBy: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Message Buyer'), findsOneWidget);
  });

  testWidgets('unread indicator shows on message button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderMessagesButton(
            order: Order.fromJson(_orderJson(unread: 2)),
            isSellerView: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('order-unread-dot')), findsOneWidget);
  });

  testWidgets('conversation screen opens', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderConversationScreen(
          orderId: 'o1',
          orderNumber: 'SB-545661',
          viewerIsSeller: false,
          pollInterval: Duration.zero,
          fetchMessages: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OrderConversationScreen), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Order #SB-545661'), findsOneWidget);
  });

  testWidgets('conversation screen empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderConversationScreen(
          orderId: 'o1',
          orderNumber: 'SB-545661',
          viewerIsSeller: false,
          pollInterval: Duration.zero,
          fetchMessages: (_) async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-conversation-screen')), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(
      find.text(
        'Use this space to communicate with the seller about your order.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('conversation renders buyer and seller messages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderConversationScreen(
          orderId: 'o1',
          orderNumber: 'SB-545661',
          viewerIsSeller: false,
          pollInterval: Duration.zero,
          fetchMessages: (_) async => [
            {
              'id': 'm1',
              'orderId': 'o1',
              'senderId': 'buyer',
              'message': 'Can I collect at 5:30?',
              'createdAt': '2026-09-18T10:00:00.000Z',
              'senderRole': 'buyer',
            },
            {
              'id': 'm2',
              'orderId': 'o1',
              'senderId': 'seller',
              'message': 'Yes, that\'s fine.',
              'createdAt': '2026-09-18T10:01:00.000Z',
              'senderRole': 'seller',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Can I collect at 5:30?'), findsOneWidget);
    expect(find.text('Yes, that\'s fine.'), findsOneWidget);
    expect(find.text('Buyer'), findsOneWidget);
    expect(find.text('Seller'), findsOneWidget);
  });

  testWidgets('send message appends and clears input', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: OrderConversationScreen(
          orderId: 'o1',
          orderNumber: 'SB-545661',
          viewerIsSeller: true,
          pollInterval: Duration.zero,
          fetchMessages: (_) async => [],
          sendMessage: (orderId, message) async {
            sent.add(message);
            return {
              'id': 'm-new',
              'orderId': orderId,
              'senderId': 'seller',
              'message': message,
              'createdAt': '2026-09-18T10:02:00.000Z',
              'senderRole': 'seller',
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('message-input')),
      'Yes, that works.',
    );
    await tester.tap(find.byKey(const Key('send-message-button')));
    await tester.pumpAndSettle();

    expect(sent, ['Yes, that works.']);
    expect(find.text('Yes, that works.'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    final field = tester.widget<TextField>(
      find.byKey(const Key('message-input')),
    );
    expect(field.controller?.text, isEmpty);
  });
}
