import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/buyer_preorders_screen.dart';
import 'package:societybites/widgets/preorder_widgets.dart';

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
  testWidgets('See all paints AppBar and seeded campaigns on first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BuyerPreOrdersScreen(initialCampaigns: [_campaign()]),
      ),
    );
    await tester.pump();

    expect(find.byType(BuyerPreOrdersScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Pre-orders'), findsOneWidget);
    expect(find.text('Friday Evening Specials'), findsOneWidget);
    expect(find.text('Sharma Snacks'), findsWidgets);
    expect(find.byType(BuyerPreOrderCampaignCard), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
