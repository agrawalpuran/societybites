import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/seller_order_history.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/screens/seller_older_orders_screen.dart';

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

Map<String, dynamic> _listing(String name) {
  return {
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 80,
  };
}

Map<String, dynamic> _orderJson({
  required String id,
  required String name,
  required DateTime at,
  String status = 'pending',
}) {
  final iso = at.toUtc().toIso8601String();
  return {
    'id': id,
    'orderNumber': 'SB-$id',
    'status': status,
    'type': 'regular',
    'total': 80,
    'subtotal': 80,
    'communityFee': 0,
    'createdAt': iso,
    if (status == 'completed') 'completedAt': iso,
    if (status == 'cancelled') 'cancelledAt': iso,
    if (status == 'rejected') 'rejectedAt': iso,
    'items': [
      {
        'quantity': 1,
        'unitPrice': 80,
        'listing': _listing(name),
      },
    ],
  };
}

Future<void> _pumpKitchen(
  WidgetTester tester, {
  required List<Map<String, dynamic>> orders,
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
        fetchCampaigns: () async => const [],
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_ignoreOverflow);

  final now = DateTime.now();

  test('recent past cutoff is 7 IST calendar days inclusive', () {
    final cutoff = sellerRecentPastCutoff(DateTime.parse('2026-09-27T10:00:00.000+05:30'));
    expect(cutoff.toUtc(), DateTime.parse('2026-09-20T18:30:00.000Z'));
  });

  test('terminal orders older than the window are not recent past', () {
    expect(
      isSellerRecentPastOrder(
        isTerminal: true,
        completedAt: now.subtract(const Duration(days: 10)),
        now: now,
      ),
      isFalse,
    );
    expect(
      isSellerRecentPastOrder(
        isTerminal: true,
        completedAt: now.subtract(const Duration(days: 2)),
        now: now,
      ),
      isTrue,
    );
    expect(
      isSellerRecentPastOrder(
        isTerminal: false,
        createdAt: now.subtract(const Duration(days: 20)),
        now: now,
      ),
      isFalse,
    );
  });

  testWidgets('active order older than 7 days stays in Active', (tester) async {
    await _pumpKitchen(tester, orders: [
      _orderJson(
        id: 'old-active',
        name: 'Idli',
        status: 'pending',
        at: now.subtract(const Duration(days: 10)),
      ),
    ]);
    expect(find.text('Idli'), findsWidgets);
    expect(find.textContaining('Active (1)'), findsOneWidget);
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('Idli'), findsNothing);
  });

  testWidgets('completed order today and 5 days ago appear in Past', (
    tester,
  ) async {
    await _pumpKitchen(tester, orders: [
      _orderJson(
        id: 'today',
        name: 'Dosa',
        status: 'completed',
        at: now,
      ),
      _orderJson(
        id: 'five',
        name: 'Thepla',
        status: 'completed',
        at: now.subtract(const Duration(days: 5)),
      ),
    ]);
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('RECENT ORDERS'), findsOneWidget);
    expect(find.text('Dosa'), findsWidgets);
    expect(find.text('Thepla'), findsWidgets);
  });

  testWidgets('completed order 10 days ago is not in default Past', (
    tester,
  ) async {
    await _pumpKitchen(tester, orders: [
      _orderJson(
        id: 'old',
        name: 'Samosa',
        status: 'completed',
        at: now.subtract(const Duration(days: 10)),
      ),
    ]);
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('Samosa'), findsNothing);
    expect(find.text('No recent orders'), findsOneWidget);
    expect(find.text('Older Orders'), findsOneWidget);
    expect(find.text('Orders older than 7 days'), findsOneWidget);
  });

  testWidgets('Older Orders opens historical orders on demand', (tester) async {
    await _pumpKitchen(tester, orders: [
      _orderJson(
        id: 'recent',
        name: 'Chapati',
        status: 'completed',
        at: now.subtract(const Duration(days: 1)),
      ),
      _orderJson(
        id: 'old',
        name: 'Samosa',
        status: 'completed',
        at: now.subtract(const Duration(days: 10)),
      ),
    ]);
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('Chapati'), findsWidgets);
    expect(find.text('Samosa'), findsNothing);
    await tester.tap(find.text('Older Orders'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SellerOlderOrdersScreen), findsOneWidget);
    expect(find.text('Samosa'), findsWidgets);
  });

  testWidgets('older list paginates instead of mounting every card at once', (
    tester,
  ) async {
    final orders = [
      for (var i = 0; i < 25; i++)
        _orderJson(
          id: 'old-$i',
          name: i == 0 ? 'FirstOld' : 'Batch $i',
          status: 'completed',
          at: now.subtract(Duration(days: 10 + (i % 5))),
        ),
    ];
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SellerOlderOrdersScreen(fetchOrders: () async => orders),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(SellerPastOrderCard), findsWidgets);
    expect(
      tester.widgetList(find.byType(SellerPastOrderCard)).length,
      lessThanOrEqualTo(20),
    );
    expect(find.text('FirstOld'), findsWidgets);
  });

  testWidgets('no older orders hides the Older Orders row', (tester) async {
    await _pumpKitchen(tester, orders: [
      _orderJson(
        id: 'recent',
        name: 'Idli',
        status: 'completed',
        at: now,
      ),
    ]);
    await tester.tap(find.textContaining('Past'));
    await tester.pump();
    expect(find.text('Older Orders'), findsNothing);
  });

  testWidgets('empty older screen copy', (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: SellerOlderOrdersScreen(
          fetchOrders: _emptyOrders,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('No older orders'), findsOneWidget);
  });
}

Future<List<Map<String, dynamic>>> _emptyOrders() async => const [];
