import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/preorder_detail_screen.dart';
import 'package:societybites/screens/seller_dashboard_screen.dart';
import 'package:societybites/widgets/app_header.dart';
import 'package:societybites/widgets/content_skeleton.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> campaignJson() {
    final now = DateTime.now();
    return {
      'id': 'campaign-1',
      'sellerId': 'seller-1',
      'title': 'Friday snacks',
      'status': 'open',
      'orderOpenAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'orderCutoffAt': now.add(const Duration(hours: 5)).toIso8601String(),
      'fulfilmentAt': now.add(const Duration(days: 1)).toIso8601String(),
      'products': const [],
    };
  }

  testWidgets('My Kitchen keeps its shell and can refresh a slow load', (
    tester,
  ) async {
    final orders = Completer<List<Map<String, dynamic>>>();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: SellerDashboardScreen(
          fetchOrders: () => orders.future,
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.text('Orders'), findsWidgets);
    expect(find.byKey(const Key('my-kitchen-add-listing')), findsOneWidget);
    expect(find.byKey(const Key('kitchen-orders-skeletons')), findsOneWidget);

    await tester.pump(loadSlowThreshold);

    expect(find.text('Taking longer than expected.'), findsWidgets);
    await tester.tap(find.byKey(const Key('kitchen-orders-refresh')));
    orders.complete(const []);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('kitchen-orders-skeletons')), findsNothing);
    expect(find.textContaining('No active orders yet'), findsOneWidget);
  });

  testWidgets('My Kitchen first-load failure keeps the shell and retries', (
    tester,
  ) async {
    var calls = 0;
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_role': 'seller',
      'user_name': 'Anita',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SellerDashboardScreen(
          fetchOrders: () async {
            calls++;
            if (calls == 1) throw Exception('offline');
            return const [];
          },
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.text("We couldn't load this right now."), findsOneWidget);
    expect(
      find.text('Please check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Exception: offline'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kitchen-orders-try-again')));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.textContaining('No active orders yet'), findsOneWidget);
  });

  testWidgets('Pre-order details shows skeletons instead of a blank loader', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreOrderDetailScreen(
                      campaignId: 'campaign-1',
                      fetchCampaign: () => pending.future,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pre-order details'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byKey(const Key('preorder-detail-skeletons')), findsOneWidget);
    expect(find.text('Loading pre-order…'), findsNothing);

    pending.complete(campaignJson());
    await tester.pump();
    await tester.pump();

    expect(find.text('Friday snacks'), findsOneWidget);
    expect(find.byKey(const Key('preorder-detail-skeletons')), findsNothing);
  });

  testWidgets('Pre-order details failure keeps the title and retries', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PreOrderDetailScreen(
          campaignId: 'campaign-1',
          fetchCampaign: () async {
            calls++;
            if (calls == 1) throw Exception('offline');
            return campaignJson();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Pre-order details'), findsOneWidget);
    expect(find.text("We couldn't load this right now."), findsOneWidget);
    await tester.tap(find.byKey(const Key('preorder-detail-try-again')));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.text('Friday snacks'), findsOneWidget);
  });
}
