import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/widgets/preorder_widgets.dart';

PreOrderCampaign _campaign({
  String? coverImageUrl,
  String status = 'open',
  DateTime? orderOpenAt,
  DateTime? orderCutoffAt,
  DateTime? fulfilmentAt,
}) {
  final now = DateTime.now();
  return PreOrderCampaign(
    id: 'campaign-1',
    sellerId: 'seller-1',
    title: 'Friday Evening Specials',
    coverImageUrl: coverImageUrl,
    status: status,
    orderOpenAt: orderOpenAt ?? now.subtract(const Duration(hours: 1)),
    orderCutoffAt: orderCutoffAt ?? now.add(const Duration(hours: 5)),
    fulfilmentAt: fulfilmentAt ?? now.add(const Duration(days: 1)),
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
  testWidgets('missing campaign cover uses pre-order placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PreOrderCoverImage(imageUrl: null)),
      ),
    );

    expect(
      find.byKey(const ValueKey('preorder-cover-placeholder')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.event_note_rounded), findsOneWidget);
  });

  testWidgets('campaign cover creates a network image', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PreOrderCoverImage(
            imageUrl: 'https://example.com/preorder-cover.jpg',
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('preorder-cover-image')), findsOneWidget);
  });

  testWidgets('seller campaign card includes its cover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreOrderCampaignCard(
            campaign: _campaign(coverImageUrl: '/uploads/seller-cover.jpg'),
            onTap: () {},
          ),
        ),
      ),
    );

    final cover = tester.widget<PreOrderCoverImage>(
      find.byType(PreOrderCoverImage),
    );
    expect(cover.imageUrl, '/uploads/seller-cover.jpg');
  });

  testWidgets('home compact card shows discovery details only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePreOrderCampaignCard(
            campaign: _campaign(coverImageUrl: '/uploads/home-cover.jpg'),
            onTap: () {},
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(HomePreOrderCampaignCard));
    expect(size.width, HomePreOrderCampaignCard.cardWidth);
    expect(size.height, HomePreOrderCampaignCard.cardHeight);

    final cover = tester.widget<PreOrderCoverImage>(
      find.byType(PreOrderCoverImage),
    );
    expect(cover.imageUrl, '/uploads/home-cover.jpg');
    expect(cover.height, HomePreOrderCampaignCard.coverHeight);
    expect(find.text('Friday Evening Specials'), findsOneWidget);
    expect(find.text('Sharma Snacks'), findsOneWidget);
    expect(find.textContaining('PRE-ORDER'), findsOneWidget);
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.textContaining('Samosa'), findsNothing);
  });

  testWidgets('home compact card marks the seller own campaign', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePreOrderCampaignCard(
            campaign: _campaign(),
            isOwn: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Yours'), findsOneWidget);
    final size = tester.getSize(find.byType(HomePreOrderCampaignCard));
    expect(size.width, HomePreOrderCampaignCard.cardWidth);
    expect(size.height, HomePreOrderCampaignCard.cardHeight);
  });

  testWidgets('home compact card uses cover placeholder when missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePreOrderCampaignCard(campaign: _campaign(), onTap: () {}),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('preorder-cover-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('buyer campaign card includes its cover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerPreOrderCampaignCard(
            campaign: _campaign(coverImageUrl: '/uploads/buyer-cover.jpg'),
            onTap: () {},
          ),
        ),
      ),
    );

    final cover = tester.widget<PreOrderCoverImage>(
      find.byType(PreOrderCoverImage),
    );
    expect(cover.imageUrl, '/uploads/buyer-cover.jpg');
  });

  testWidgets('home compact card shows coming soon before order open', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePreOrderCampaignCard(
            campaign: _campaign(
              orderOpenAt: now.add(const Duration(days: 1)),
              orderCutoffAt: now.add(const Duration(days: 2)),
              fulfilmentAt: now.add(const Duration(days: 3)),
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('COMING SOON'), findsOneWidget);
    expect(find.textContaining('Opens'), findsOneWidget);
  });

  testWidgets('home compact card shows orders closed until fulfilment', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePreOrderCampaignCard(
            campaign: _campaign(
              status: 'closed',
              orderOpenAt: now.subtract(const Duration(days: 3)),
              orderCutoffAt: now.subtract(const Duration(hours: 1)),
              fulfilmentAt: now.add(const Duration(days: 1)),
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('ORDERS CLOSED'), findsOneWidget);
    expect(find.textContaining('Ready'), findsOneWidget);
  });
}
