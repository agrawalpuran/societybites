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

  testWidgets('closed campaign stays viewable without add actions', (
    tester,
  ) async {
    final now = DateTime.now();
    final closed = PreOrderCampaign(
      id: 'campaign-1',
      sellerId: 'seller-1',
      title: 'Sunday Cake Special',
      status: 'closed',
      orderOpenAt: now.subtract(const Duration(days: 3)),
      orderCutoffAt: now.subtract(const Duration(hours: 2)),
      fulfilmentAt: now.add(const Duration(days: 1)),
      products: const [
        PreOrderProduct(
          listingId: 'listing-1',
          name: 'Chocolate Truffle Cake',
          sellerId: 'seller-1',
          sellerName: 'Puran Agrawal',
          price: 900,
          inventoryMode: 'demand',
          quantity: 0,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BuyerPreOrderDetailScreen(
          campaignId: 'campaign-1',
          initialCampaign: closed,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ORDERS CLOSED'), findsWidgets);
    expect(find.text('Chocolate Truffle Cake'), findsOneWidget);
    final continueButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue Pre-order'),
    );
    expect(continueButton.onPressed, isNull);
  });
}
