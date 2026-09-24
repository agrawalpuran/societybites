import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/widgets/seller_insights_panel.dart';

void main() {
  test('quantitySold is independent of remaining inventory', () {
    final item = FoodItem.fromJson({
      'id': 'listing-1',
      'name': "Dad's Dhokla",
      'sellerId': 'seller-1',
      'sellerName': 'Puran Agrawal',
      'price': 120,
      'quantity': 4,
      'quantitySold': 28,
    });
    expect(item.quantity, 4);
    expect(item.quantitySold, 28);
    expect(listingSoldCaption(item.quantitySold), '28 sold');
    expect(listingSoldCaption(0), '');
    expect(listingSoldCaption(1), '1 sold');
  });

  testWidgets('shows KPI cards and cancelled status without treating it as sales',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SellerInsightsPanel(
              fetchInsights: ({required preset, from, to}) async {
                expect(preset, 'last_7_days');
                return {
                  'empty': null,
                  'summary': {
                    'orders': 3,
                    'sales': 200,
                    'itemsSold': 2,
                    'averageOrderValue': 200,
                    'completedOrders': 1,
                  },
                  'statusBreakdown': [
                    {'status': 'completed', 'count': 1},
                    {'status': 'pending', 'count': 1},
                    {'status': 'cancelled', 'count': 1},
                  ],
                  'dailyTrend': [
                    {'date': '2026-09-22', 'orders': 2, 'sales': 200},
                    {'date': '2026-09-23', 'orders': 1, 'sales': 0},
                  ],
                  'topItems': [
                    {
                      'listingId': 'dhokla',
                      'name': "Dad's Dhokla",
                      'quantitySold': 2,
                      'sales': 200,
                    },
                  ],
                  'recentOrders': [
                    {
                      'id': '1',
                      'orderNumber': 'SB-1',
                      'buyerName': 'Asha',
                      'amount': 200,
                      'status': 'completed',
                      'createdAt': '2026-09-22T04:30:00.000Z',
                    },
                  ],
                };
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('Orders'), findsWidgets);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Sales (₹)'), findsOneWidget);
    expect(find.text('Order status'), findsOneWidget);
    expect(find.text('₹200'), findsWidgets);
    expect(find.text("Dad's Dhokla"), findsOneWidget);
    expect(find.text('2 sold'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('SB-1'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('22'), findsWidgets);
    expect(find.text('23'), findsWidgets);
  });

  testWidgets('See all recent orders invokes the callback', (tester) async {
    var seeAll = false;
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SellerInsightsPanel(
              showHeading: false,
              onSeeAllOrders: () => seeAll = true,
              fetchInsights: ({required preset, from, to}) async => {
                'empty': null,
                'summary': {
                  'orders': 1,
                  'sales': 100,
                  'itemsSold': 1,
                  'averageOrderValue': 100,
                },
                'statusBreakdown': [
                  {'status': 'completed', 'count': 1},
                ],
                'dailyTrend': [
                  {'date': '2026-09-23', 'orders': 1, 'sales': 100},
                ],
                'topItems': const [],
                'recentOrders': [
                  {
                    'id': '1',
                    'orderNumber': 'SB-9',
                    'buyerName': 'Asha',
                    'amount': 100,
                    'status': 'completed',
                    'createdAt': '2026-09-23T04:30:00.000Z',
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Insights'), findsNothing);
    await tester.ensureVisible(find.text('See all'));
    await tester.tap(find.text('See all'));
    await tester.pump();
    expect(seeAll, isTrue);
  });

  testWidgets('empty lifetime state is friendly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerInsightsPanel(
            fetchInsights: ({required preset, from, to}) async => {
              'empty': 'none',
              'summary': {
                'orders': 0,
                'sales': 0,
                'itemsSold': 0,
                'averageOrderValue': 0,
              },
              'statusBreakdown': [],
              'dailyTrend': [],
              'topItems': [],
              'recentOrders': [],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No orders yet'), findsOneWidget);
    expect(
      find.text(
        'Your sales insights will appear here once customers start ordering.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('analytics failure stays retryable', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerInsightsPanel(
            fetchInsights: ({required preset, from, to}) async {
              calls += 1;
              throw Exception('network down');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Insights are unavailable right now.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
