import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/preorder_detail_screen.dart';

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
      'products': const [
        {
          'id': 'listing-1',
          'name': 'Besan Kachori',
          'sellerId': 'seller-1',
          'sellerName': 'Puran',
          'price': 25,
        },
      ],
    };
  }

  testWidgets('new campaign stays open so more products can be added', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PreOrderDetailScreen(
                      campaignId: 'campaign-1',
                      promptToAddProduct: true,
                      fetchCampaign: () async => campaignJson(),
                    ),
                  ),
                );
              },
              child: const Text('open campaign'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open campaign'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Besan Kachori'), findsOneWidget);
    expect(find.text('Add product'), findsWidgets);
    expect(find.text('Close orders'), findsNothing);

    await tester.ensureVisible(find.text('Save campaign'));
    await tester.pumpAndSettle();
    expect(find.text('Save campaign'), findsOneWidget);

    await tester.tap(find.text('Save campaign'));
    await tester.pumpAndSettle();

    expect(find.text('Pre-order details'), findsNothing);
    expect(find.text('open campaign'), findsOneWidget);
  });
}
