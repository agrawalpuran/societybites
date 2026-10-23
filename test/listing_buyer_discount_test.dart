import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/coupon.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/listing_discount.dart';
import 'package:societybites/models/seller_fulfilment.dart';
import 'package:societybites/screens/checkout_screen.dart';
import 'package:societybites/screens/food_detail_screen.dart';
import 'package:societybites/screens/home_listing_filter.dart';
import 'package:societybites/services/cart_controller.dart';
import 'package:societybites/services/listing_variants_cache.dart';
import 'package:societybites/utils/listing_portion_label.dart';
import 'package:societybites/widgets/listing_buyer_price.dart';
import 'package:societybites/widgets/listing_variant_picker_sheet.dart';
import 'package:societybites/widgets/order_items_list.dart';

Map<String, dynamic> _listingJson({
  required String id,
  double price = 200,
  bool? discountActive,
  double? effectivePrice,
  double? discountPercent,
  bool? discountEnabled,
  String? variantGroupId,
  String? variantLabel,
  int quantity = 8,
}) {
  return {
    'id': id,
    'name': 'Samosa',
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': price,
    'status': 'active',
    'quantity': quantity,
    'foodType': 'VEG',
    'category': 'Snacks',
    if (discountEnabled != null) 'discountEnabled': discountEnabled,
    if (discountPercent != null) 'discountPercent': discountPercent,
    if (discountActive != null) 'discountActive': discountActive,
    if (effectivePrice != null) 'effectivePrice': effectivePrice,
    if (variantGroupId != null) 'variantGroupId': variantGroupId,
    if (variantLabel != null) 'variantLabel': variantLabel,
  };
}

FoodItem _food({
  required String id,
  double price = 200,
  bool discountActive = false,
  double? effectivePrice,
  double? discountPercent,
  String? variantGroupId,
  String? variantLabel,
}) {
  return FoodItem.fromJson(
    _listingJson(
      id: id,
      price: price,
      discountActive: discountActive,
      effectivePrice: effectivePrice,
      discountPercent: discountPercent,
      variantGroupId: variantGroupId,
      variantLabel: variantLabel,
    ),
  );
}

void _ignoreOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    CartController.instance
      ..onOrderPlaced = null
      ..onShowOrdersAfterPlace = null
      ..clear();
  });

  group('resolveListingDisplayPrice', () {
    test('legacy listing without discount fields uses regular price', () {
      final food = FoodItem.fromJson({
        'id': 'legacy-1',
        'name': 'Idli',
        'price': 80,
      });
      final quote = listingDisplayPrice(food);
      expect(food.price, 80);
      expect(food.discountActive, isFalse);
      expect(food.effectivePrice, isNull);
      expect(quote.chargedPrice, 80);
      expect(quote.regularPrice, 80);
      expect(quote.saleActive, isFalse);
    });

    test('disabled discount shows regular price only', () {
      final quote = resolveListingDisplayPrice(
        regularPrice: 200,
        discountActive: false,
        effectivePrice: 180,
        discountPercent: 10,
      );
      expect(quote.chargedPrice, 200);
      expect(quote.saleActive, isFalse);
    });

    test('expired metadata without discountActive does not show a sale', () {
      final food = _food(
        id: 'expired',
        price: 200,
        discountActive: false,
        effectivePrice: 180,
        discountPercent: 10,
      );
      expect(listingDisplayPrice(food).saleActive, isFalse);
      expect(listingBuyerUnitPrice(food), 200);
    });

    test('active discount uses backend effectivePrice', () {
      final quote = resolveListingDisplayPrice(
        regularPrice: 200,
        discountActive: true,
        effectivePrice: 180,
        discountPercent: 10,
      );
      expect(quote.regularPrice, 200);
      expect(quote.chargedPrice, 180);
      expect(quote.saleActive, isTrue);
      expect(quote.discountPercent, 10);
    });

    test('missing effectivePrice falls back to regular', () {
      final quote = resolveListingDisplayPrice(
        regularPrice: 200,
        discountActive: true,
      );
      expect(quote.chargedPrice, 200);
      expect(quote.saleActive, isFalse);
    });

    test('effectivePrice at or above regular is not a sale', () {
      expect(
        resolveListingDisplayPrice(
          regularPrice: 200,
          discountActive: true,
          effectivePrice: 200,
        ).saleActive,
        isFalse,
      );
      expect(
        resolveListingDisplayPrice(
          regularPrice: 200,
          discountActive: true,
          effectivePrice: 250,
        ).chargedPrice,
        200,
      );
    });

    test('non-finite effectivePrice falls back to regular', () {
      final quote = resolveListingDisplayPrice(
        regularPrice: 150,
        discountActive: true,
        effectivePrice: double.nan,
      );
      expect(quote.chargedPrice, 150);
      expect(quote.saleActive, isFalse);
    });
  });

  group('catalogue from ₹ pairing', () {
    test('from ₹ uses the lowest charged price among siblings', () {
      final small = _food(
        id: 'small',
        price: 150,
        discountActive: true,
        effectivePrice: 90,
        discountPercent: 40,
        variantGroupId: 'g1',
        variantLabel: 'Small',
      );
      final large = _food(
        id: 'large',
        price: 100,
        variantGroupId: 'g1',
        variantLabel: 'Large',
      );
      expect(
        listingCardPriceLabel(small, variants: [small, large]),
        'from ₹90',
      );
      final cheapest = cheapestBuyerVariant([small, large]);
      expect(cheapest.id, 'small');
      expect(listingDisplayPrice(cheapest).regularPrice, 150);
      expect(listingDisplayPrice(cheapest).chargedPrice, 90);
    });

    test('collapse keeps the cheapest charged SKU as the card', () {
      final small = _food(
        id: 'small',
        price: 150,
        discountActive: true,
        effectivePrice: 90,
        variantGroupId: 'g1',
      );
      final large = _food(
        id: 'large',
        price: 100,
        variantGroupId: 'g1',
      );
      final collapsed = collapseListingVariants([large, small]);
      expect(collapsed, hasLength(1));
      expect(collapsed.single.id, 'small');
      expect(listingBuyerUnitPrice(collapsed.single), 90);
      expect(collapsed.single.price, 150);
    });
  });

  group('cart line totals', () {
    test('line total uses effective unit price once', () {
      final item = CartItem(
        food: _food(
          id: 'sale',
          price: 200,
          discountActive: true,
          effectivePrice: 180,
          discountPercent: 10,
        ),
        quantity: 2,
      );
      expect(item.total, 360);
      item.quantity = 3;
      expect(item.total, 540);
    });

    test('inactive cart line keeps regular price', () {
      final item = CartItem(
        food: _food(id: 'plain', price: 75),
        quantity: 2,
      );
      expect(item.total, 150);
    });

    test('removing a line leaves remaining charged totals', () {
      final sale = CartItem(
        food: _food(
          id: 'sale',
          price: 200,
          discountActive: true,
          effectivePrice: 180,
        ),
      );
      final plain = CartItem(food: _food(id: 'plain', price: 50), quantity: 2);
      CartController.instance.replaceItems([sale, plain]);
      expect(CartController.instance.total, 280);
      CartController.instance.replaceItems([plain]);
      expect(CartController.instance.items, hasLength(1));
      expect(CartController.instance.total, 100);
    });

    test('stale cart FoodItem is not treated as the charged amount', () {
      final staleSale = _food(
        id: 'listing-1',
        price: 200,
        discountActive: true,
        effectivePrice: 180,
      );
      final liveRegular = _food(id: 'listing-1', price: 200);
      final cart = CartItem(food: staleSale, quantity: 1);
      expect(cart.total, 180);
      expect(listingBuyerUnitPrice(liveRegular), 200);
      final payload = {
        'listingId': cart.food.id,
        'quantity': cart.quantity,
      };
      expect(payload.containsKey('unitPrice'), isFalse);
      expect(payload.containsKey('effectivePrice'), isFalse);
    });
  });

  group('checkout food subtotal vs fees and coupons', () {
    test('coupon amount is not mixed into listing discount math', () {
      final foodSubtotal = CartItem(
        food: _food(
          id: 'sale',
          price: 200,
          discountActive: true,
          effectivePrice: 180,
        ),
      ).total;
      const platformFee = 5.0;
      const delivery = 20.0;
      final coupon = CouponQuote.fromJson({
        'code': 'WELCOME20',
        'discountAmount': 20,
        'orderSubtotal': foodSubtotal,
        'buyerPayable': foodSubtotal + platformFee + delivery - 20,
        'sellerGrossAmount': foodSubtotal,
        'societyEatsSubsidy': 20,
      });
      final grand = (foodSubtotal + platformFee + delivery - coupon.discountAmount)
          .clamp(0, double.infinity);
      expect(foodSubtotal, 180);
      expect(grand, 185);
    });

    testWidgets('checkout shows charged subtotal and quantity still works', (
      tester,
    ) async {
      _ignoreOverflow();
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: CheckoutScreen(
            cartItems: [
              CartItem(
                food: _food(
                  id: 'sale-sku',
                  price: 200,
                  discountActive: true,
                  effectivePrice: 180,
                  discountPercent: 10,
                ),
              ),
            ],
            sellerFulfilment: const SellerFulfilment(
              mode: FulfilmentMode.buyerPickup,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('₹180'), findsWidgets);
      expect(find.text('₹200'), findsWidgets);
      expect(find.text('10% off'), findsWidgets);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('2'), findsWidgets);
      expect(find.text('₹360'), findsWidgets);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(find.text('₹180'), findsWidgets);
    });

    test('server order items win over cart fallback snapshots', () {
      final cart = [
        CartItem(
          food: _food(
            id: 'sale-sku',
            price: 200,
            discountActive: true,
            effectivePrice: 180,
          ),
        ),
      ];
      final fromServer = Order.fromJson({
        'id': 'order-1',
        'orderNumber': 'SB-1',
        'status': 'pending',
        'total': 200,
        'subtotal': 200,
        'communityFee': 0,
        'items': [
          {
            'quantity': 1,
            'unitPrice': 200,
            'listing': _listingJson(id: 'sale-sku', price: 200),
          },
        ],
      });
      final merged = Order.withCartLineItemsIfMissing(fromServer, cart);
      expect(merged.items.single.unitPrice, 200);
      expect(merged.items.single.lineTotal, 200);
    });

    test('missing create-order items fall back to charged cart prices', () {
      final cart = [
        CartItem(
          food: _food(
            id: 'sale-sku',
            price: 200,
            discountActive: true,
            effectivePrice: 180,
            discountPercent: 10,
          ),
          quantity: 2,
        ),
      ];
      final sparse = Order.fromJson({
        'id': 'order-1',
        'orderNumber': 'SB-1',
        'status': 'pending',
        'total': 360,
        'subtotal': 360,
        'communityFee': 0,
        'items': <Object>[],
      });
      final merged = Order.withCartLineItemsIfMissing(sparse, cart);
      expect(merged.items.single.unitPrice, 180);
      expect(merged.items.single.originalUnitPrice, 200);
      expect(merged.items.single.lineTotal, 360);
    });
  });

  group('historical order snapshots', () {
    test('line totals use snapshotted unitPrice, not live listing price', () {
      final item = OrderLineItem.fromJson({
        'quantity': 2,
        'unitPrice': 180,
        'originalUnitPrice': 200,
        'discountPercent': 10,
        'listing': _listingJson(
          id: 'sale-sku',
          price: 250,
          discountActive: true,
          effectivePrice: 225,
        ),
      });
      expect(item.lineTotal, 360);
      expect(item.food.price, 250);
      expect(item.unitPrice, 180);
    });

    test('old orders with null snapshot fields still total from unitPrice', () {
      final item = OrderLineItem.fromJson({
        'quantity': 3,
        'unitPrice': 80,
        'listing': {
          'id': 'legacy',
          'name': 'Idli',
          'price': 90,
        },
      });
      expect(item.originalUnitPrice, isNull);
      expect(item.discountPercent, isNull);
      expect(item.lineTotal, 240);
    });

    testWidgets('history shows original price only when snapshotted', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderItemsList(
              items: [
                OrderLineItem.fromJson({
                  'quantity': 2,
                  'unitPrice': 180,
                  'originalUnitPrice': 200,
                  'discountPercent': 10,
                  'listing': _listingJson(id: 'sale-sku', price: 250),
                }),
              ],
            ),
          ),
        ),
      );
      expect(find.text('₹360'), findsOneWidget);
      expect(find.text('₹400'), findsOneWidget);
      expect(find.text('10% off'), findsOneWidget);
    });

    testWidgets('old history lines render without a sale badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderItemsList(
              items: [
                OrderLineItem.fromJson({
                  'quantity': 1,
                  'unitPrice': 80,
                  'listing': {'id': 'legacy', 'name': 'Idli', 'price': 80},
                }),
              ],
            ),
          ),
        ),
      );
      expect(find.text('₹80'), findsOneWidget);
      expect(find.text('10% off'), findsNothing);
    });
  });

  group('buyer widgets', () {
    testWidgets('active discount shows charged price and strike-through', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListingBuyerPriceText(
              food: _food(
                id: 'sale',
                price: 200,
                discountActive: true,
                effectivePrice: 180,
                discountPercent: 10,
              ),
            ),
          ),
        ),
      );
      expect(find.text('₹180'), findsOneWidget);
      expect(find.text('₹200'), findsOneWidget);
      expect(find.text('10% off'), findsOneWidget);
    });

    testWidgets('inactive discount does not show a sale badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListingBuyerPriceText(
              food: _food(
                id: 'plain',
                price: 200,
                discountActive: false,
                effectivePrice: 180,
                discountPercent: 10,
              ),
            ),
          ),
        ),
      );
      expect(find.text('₹200'), findsOneWidget);
      expect(find.text('₹180'), findsNothing);
      expect(find.text('10% off'), findsNothing);
    });

    testWidgets('food detail footer uses the charged price', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FoodDetailScreen(
            food: _food(
              id: 'sale',
              price: 200,
              discountActive: true,
              effectivePrice: 180,
              discountPercent: 10,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('₹180'), findsWidgets);
      expect(find.text('₹200'), findsWidgets);
      expect(find.text('10% off'), findsWidgets);
    });

    testWidgets('variant picker shows each SKU price independently', (
      tester,
    ) async {
      final small = _food(
        id: 'small',
        price: 100,
        discountActive: true,
        effectivePrice: 80,
        discountPercent: 20,
        variantGroupId: 'picker-g',
        variantLabel: 'Small',
      );
      ListingVariantsCache.put(small, [
        _listingJson(
          id: 'small',
          price: 100,
          discountActive: true,
          effectivePrice: 80,
          discountPercent: 20,
          variantGroupId: 'picker-g',
          variantLabel: 'Small',
        ),
        _listingJson(
          id: 'large',
          price: 220,
          variantGroupId: 'picker-g',
          variantLabel: 'Large',
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListingVariantPickerSheet(seed: small, asWebDialog: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Small'), findsWidgets);
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('₹80'), findsWidgets);
      expect(find.text('₹100'), findsWidgets);
      expect(find.text('₹220'), findsOneWidget);
      expect(find.text('Add Item | ₹80'), findsOneWidget);
    });
  });
}
