import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/buyer_preorder_detail_screen.dart';

PreOrderCampaign _campaign() {
  final now = DateTime.now();
  return PreOrderCampaign(
    id: 'campaign-1',
    sellerId: 'seller-1',
    title: 'Friday Evening Specials',
    status: 'open',
    orderOpenAt: now.subtract(const Duration(hours: 1)),
    orderCutoffAt: now.add(const Duration(hours: 5)),
    fulfilmentAt: now.add(const Duration(days: 1)),
    products: const [
      PreOrderProduct(
        listingId: 'listing-1',
        name: 'Samosa',
        sellerId: 'seller-1',
        sellerName: 'Sharma Snacks',
        price: 20,
        inventoryMode: 'demand',
        quantity: 0,
      ),
    ],
  );
}

void main() {
  testWidgets('campaign detail keeps products visible above continue bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BuyerPreOrderDetailScreen(
          campaignId: 'campaign-1',
          initialCampaign: _campaign(),
        ),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(AppBar, 'Pre-order'), findsOneWidget);
    expect(find.text('Friday Evening Specials'), findsOneWidget);
    expect(find.text('CHOOSE PRODUCTS'), findsOneWidget);
    expect(find.text('Samosa'), findsOneWidget);
    expect(find.text('Continue Pre-order'), findsOneWidget);

    final screenHeight =
        (tester.view.physicalSize / tester.view.devicePixelRatio).height;
    final footer = tester.getRect(find.text('Continue Pre-order'));
    final title = tester.getRect(find.text('Friday Evening Specials'));

    expect(footer.height, lessThan(80));
    expect(title.top, greaterThan(40));
    expect(title.bottom, lessThan(footer.top));
    expect(footer.bottom, lessThanOrEqualTo(screenHeight));
  });
}
