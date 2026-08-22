import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/seller_list_screen.dart';
import 'package:societybites/widgets/preorder_widgets.dart';

FoodItem _food({
  required String id,
  required double rating,
  required int reviews,
}) {
  return FoodItem(
    id: id,
    name: 'Product $id',
    sellerId: 'seller-1',
    sellerName: 'Puran Agrawal',
    block: 'Block A',
    price: 25,
    rating: rating,
    pickupTime: '5:00 PM',
    description: '',
    reviewCount: reviews,
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
  );
}

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
        sellerName: 'Puran Agrawal',
        block: 'Block A',
        rating: 4.5,
        reviewCount: 2,
        price: 20,
        inventoryMode: 'demand',
        quantity: 0,
      ),
    ],
  );
}

void main() {
  test('seller metadata aggregates listing ratings and review counts', () {
    final sellers = sellersFromListings([
      _food(id: 'one', rating: 5, reviews: 2),
      _food(id: 'two', rating: 4, reviews: 1),
    ]);

    expect(sellers, hasLength(1));
    expect(sellers.single.reviewCount, 3);
    expect(sellers.single.rating, closeTo(4.666, .01));
  });

  test('campaign provides seller metadata for storefront navigation', () {
    final seller = sellerFromPreOrderCampaign(_campaign());

    expect(seller.id, 'seller-1');
    expect(seller.name, 'Puran Agrawal');
    expect(seller.block, 'Block A');
    expect(seller.reviewCount, 2);
  });

  testWidgets('seller list row invokes storefront navigation callback', (
    tester,
  ) async {
    Seller? selected;
    final seller = sellerFromListing(
      _food(id: 'one', rating: 4.8, reviews: 5),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SellerListScreen(
          sellers: [seller],
          onSellerTap: (value) => selected = value,
        ),
      ),
    );

    await tester.tap(find.text('Puran Agrawal'));
    await tester.pump();

    expect(selected?.id, 'seller-1');
  });

  testWidgets('campaign seller name has a separate seller action', (
    tester,
  ) async {
    var campaignOpened = false;
    var sellerOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuyerPreOrderCampaignCard(
            campaign: _campaign(),
            onTap: () => campaignOpened = true,
            onSellerTap: () => sellerOpened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Puran Agrawal'));
    await tester.pump();

    expect(sellerOpened, isTrue);
    expect(campaignOpened, isFalse);
  });
}
