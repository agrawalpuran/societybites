import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/widgets/preorder_widgets.dart';

PreOrderCampaign _campaign({String? coverImageUrl}) {
  return PreOrderCampaign(
    id: 'campaign-1',
    sellerId: 'seller-1',
    title: 'Friday Evening Specials',
    coverImageUrl: coverImageUrl,
    status: 'open',
    orderOpenAt: DateTime(2026, 8, 22, 10),
    orderCutoffAt: DateTime(2026, 8, 22, 20),
    fulfilmentAt: DateTime(2026, 8, 23, 10),
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
    expect(find.textContaining('By'), findsOneWidget);
    expect(find.textContaining('Samosa'), findsNothing);
    expect(find.textContaining('PRE-ORDER'), findsNothing);
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
}
