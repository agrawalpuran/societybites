import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/seller_list_screen.dart';
import 'package:societybites/screens/seller_storefront_screen.dart';
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
  setUp(SellerStorefrontMemoryCache.clear);

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

  testWidgets('first storefront open shows structure and skeletons, not a spinner', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    await _openStorefront(
      tester,
      seller: _seller('seller-a', 'Seller A'),
      fetchListings: () => pending.future,
    );
    await tester.pump();

    expect(find.text('Seller Storefront'), findsOneWidget);
    expect(find.text('Seller A'), findsOneWidget);
    expect(find.byKey(const Key('storefront-product-skeletons')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    pending.complete([
      _listingJson(id: 'a1', name: 'A Idli', sellerId: 'seller-a'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('A Idli'), findsOneWidget);
    expect(find.byKey(const Key('storefront-product-skeletons')), findsNothing);
  });

  testWidgets('first-load failure shows an inline error inside the storefront', (
    tester,
  ) async {
    await _openStorefront(
      tester,
      seller: _seller('seller-a', 'Seller A'),
      fetchListings: () async {
        throw Exception('storefront unavailable');
      },
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Seller A'), findsOneWidget);
    expect(find.text('Unable to load this store'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('reopening the same seller shows cached storefront immediately', (
    tester,
  ) async {
    var calls = 0;
    final reopenHang = Completer<List<Map<String, dynamic>>>();
    final seller = _seller('seller-a', 'Seller A');

    await _openStorefront(
      tester,
      seller: seller,
      fetchListings: () async {
        calls++;
        return [_listingJson(id: 'a1', name: 'A Idli', sellerId: 'seller-a')];
      },
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('A Idli'), findsOneWidget);
    expect(calls, 1);

    await _openStorefront(
      tester,
      seller: seller,
      fetchListings: () => reopenHang.future,
    );
    await tester.pump();

    expect(find.text('A Idli'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('background refresh replaces cached storefront after success', (
    tester,
  ) async {
    final refresh = Completer<List<Map<String, dynamic>>>();
    final seller = _seller('seller-a', 'Seller A');

    await _openStorefront(
      tester,
      seller: seller,
      fetchListings: () async {
        return [_listingJson(id: 'a1', name: 'A Idli', sellerId: 'seller-a')];
      },
    );
    await tester.pump();
    await tester.pump();

    await _openStorefront(
      tester,
      seller: seller,
      fetchListings: () => refresh.future,
    );
    await tester.pump();
    expect(find.text('A Idli'), findsOneWidget);

    refresh.complete([
      _listingJson(id: 'a2', name: 'A Dosa', sellerId: 'seller-a'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('A Dosa'), findsOneWidget);
    expect(find.text('A Idli'), findsNothing);
  });

  testWidgets('failed storefront refresh keeps cached products', (tester) async {
    final seller = _seller('seller-a', 'Seller A');
    await _openStorefront(
      tester,
      seller: seller,
      fetchListings: () async => [
        _listingJson(id: 'a1', name: 'A Idli', sellerId: 'seller-a'),
      ],
    );
    await tester.pump();
    await tester.pump();

    await _openStorefront(
      tester,
      seller: seller,
      fetchListings: () async {
        throw Exception('storefront refresh failed');
      },
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('A Idli'), findsOneWidget);
    expect(find.textContaining('storefront refresh failed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('seller A cache never appears for seller B', (tester) async {
    await _openStorefront(
      tester,
      seller: _seller('seller-a', 'Seller A'),
      fetchListings: () async => [
        _listingJson(id: 'a1', name: 'A Idli', sellerId: 'seller-a'),
      ],
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('A Idli'), findsOneWidget);

    final pendingB = Completer<List<Map<String, dynamic>>>();
    await _openStorefront(
      tester,
      seller: _seller('seller-b', 'Seller B'),
      fetchListings: () => pendingB.future,
    );
    await tester.pump();

    expect(find.text('A Idli'), findsNothing);
    expect(find.text('Seller B'), findsOneWidget);
    expect(find.byKey(const Key('storefront-product-skeletons')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    pendingB.complete([
      _listingJson(id: 'b1', name: 'B Biryani', sellerId: 'seller-b'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('B Biryani'), findsOneWidget);
    expect(find.text('A Idli'), findsNothing);
  });

  testWidgets('storefront add-to-cart still increments quantity', (tester) async {
    await _openStorefront(
      tester,
      seller: _seller('seller-a', 'Seller A'),
      fetchListings: () async => [
        _listingJson(id: 'a1', name: 'A Idli', sellerId: 'seller-a'),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('A Idli'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(find.text('1'), findsWidgets);
    expect(find.text('Add'), findsNothing);
  });
}

Map<String, dynamic> _listingJson({
  required String id,
  required String name,
  required String sellerId,
}) {
  return {
    'id': id,
    'name': name,
    'sellerId': sellerId,
    'sellerName': 'Neighbor',
    'price': 100,
    'status': 'active',
  };
}

Seller _seller(String id, String name) {
  return Seller(
    id: id,
    name: name,
    block: 'A',
    rating: 5,
    avatarIcon: Icons.restaurant,
    avatarColor: const Color(0xFFE8F5EE),
  );
}

Future<void> _openStorefront(
  WidgetTester tester, {
  required Seller seller,
  required Future<List<Map<String, dynamic>>> Function() fetchListings,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: SellerStorefrontScreen(
        key: UniqueKey(),
        seller: seller,
        fetchListings: fetchListings,
        fetchCampaigns: () async => [],
      ),
    ),
  );
}
