import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/widgets/preorder_widgets.dart';

void main() {
  test('campaign parses products and fulfilment configuration', () {
    final campaign = PreOrderCampaign.fromJson({
      'id': 'campaign-1',
      'sellerId': 'seller-1',
      'title': 'Friday Specials',
      'coverImageUrl': '/uploads/friday-specials.jpg',
      'fulfilmentNotes': 'Collect from the clubhouse entrance.',
      'status': 'open',
      'orderOpenAt': '2026-08-21T10:00:00.000Z',
      'orderCutoffAt': '2026-08-22T10:00:00.000Z',
      'fulfilmentAt': '2026-08-22T13:00:00.000Z',
      'offeredFulfilmentMethods': ['pickup', 'seller_delivery'],
      'defaultDeliveryCharge': 40,
      'products': [
        {
          'id': 'listing-1',
          'name': 'Samosa',
          'sellerId': 'seller-1',
          'sellerName': 'Sharma Snacks',
          'price': 20,
          'inventoryMode': 'demand',
          'quantity': 0,
        },
        {
          'id': 'listing-2',
          'name': 'Dhokla',
          'sellerId': 'seller-1',
          'sellerName': 'Sharma Snacks',
          'price': 30,
          'inventoryMode': 'limited',
          'quantity': 10,
        },
      ],
    });

    expect(campaign.title, 'Friday Specials');
    expect(campaign.coverImageUrl, '/uploads/friday-specials.jpg');
    expect(campaign.fulfilmentNotes, 'Collect from the clubhouse entrance.');
    expect(campaign.sellerName, 'Sharma Snacks');
    expect(campaign.startingPrice, 20);
    expect(campaign.products, hasLength(2));
    expect(campaign.products.first.inventoryMode, 'demand');
    expect(campaign.products.last.inventoryMode, 'limited');
    expect(campaign.products.last.quantity, 10);
    expect(campaign.defaultDeliveryCharge, 40);
  });

  test('summary uses backend production quantities and fulfilment counts', () {
    final summary = PreOrderSummary.fromJson({
      'campaignId': 'campaign-1',
      'title': 'Friday Specials',
      'coverImageUrl': '/uploads/friday-specials.jpg',
      'status': 'closed',
      'orderOpenAt': '2026-08-21T10:00:00.000Z',
      'orderCutoffAt': '2026-08-22T10:00:00.000Z',
      'fulfilmentAt': '2026-08-22T13:00:00.000Z',
      'totalOrders': 42,
      'totalItems': 249,
      'foodSubtotal': 8450,
      'fulfilment': {'pickup': 28, 'seller_delivery': 14},
      'products': [
        {
          'listingId': 'listing-1',
          'productName': 'Samosa',
          'quantityToPrepare': 146,
        },
      ],
    });

    expect(summary.totalOrders, 42);
    expect(summary.coverImageUrl, '/uploads/friday-specials.jpg');
    expect(summary.totalItems, 249);
    expect(summary.foodSubtotal, 8450);
    expect(summary.pickupOrders, 28);
    expect(summary.sellerDeliveryOrders, 14);
    expect(summary.products.single.quantityToPrepare, 146);
  });

  test('campaign without cover image remains valid', () {
    final campaign = PreOrderCampaign.fromJson({
      'id': 'campaign-without-cover',
      'sellerId': 'seller-1',
      'title': 'No Cover Campaign',
      'status': 'draft',
      'orderOpenAt': '2026-08-21T10:00:00.000Z',
      'orderCutoffAt': '2026-08-22T10:00:00.000Z',
      'fulfilmentAt': '2026-08-22T13:00:00.000Z',
      'products': <Map<String, dynamic>>[],
    });

    expect(campaign.coverImageUrl, isNull);
  });

  test(
    'pre-order order parses delivery snapshot without changing regular defaults',
    () {
      final preorder = Order.fromJson({
        'id': 'order-1',
        'orderNumber': 'SB-1023',
        'items': <Map<String, dynamic>>[],
        'status': 'pending',
        'type': 'pre_order',
        'campaignId': 'campaign-1',
        'fulfilmentMethod': 'seller_delivery',
        'deliveryCharge': 40,
        'subtotal': 200,
        'communityFee': 0,
        'total': 240,
        'paymentStatus': 'pending',
        'createdAt': '2026-08-22T09:00:00.000Z',
      });
      final regular = Order.fromJson({
        'id': 'order-2',
        'orderNumber': 'SB-1024',
        'items': <Map<String, dynamic>>[],
        'status': 'pending',
        'subtotal': 100,
        'communityFee': 0,
        'total': 100,
        'createdAt': '2026-08-22T09:00:00.000Z',
      });

      expect(preorder.type, 'pre_order');
      expect(preorder.fulfilmentMethod, 'seller_delivery');
      expect(preorder.deliveryCharge, 40);
      expect(regular.type, 'regular');
      expect(regular.deliveryCharge, 0);
    },
  );

  test('pre-order cancellation eligibility follows campaign cutoff', () {
    Order orderWithCutoff(DateTime cutoff) {
      final order = Order.fromJson({
        'id': 'order-1',
        'orderNumber': 'SB-1023',
        'items': <Map<String, dynamic>>[],
        'status': 'pending',
        'type': 'pre_order',
        'campaignId': 'campaign-1',
        'subtotal': 200,
        'total': 200,
        'createdAt': '2026-08-22T09:00:00.000Z',
      });
      final campaign = PreOrderCampaign.fromJson({
        'id': 'campaign-1',
        'sellerId': 'seller-1',
        'title': 'Friday Specials',
        'status': 'open',
        'orderOpenAt': '2026-08-21T10:00:00.000Z',
        'orderCutoffAt': cutoff.toIso8601String(),
        'fulfilmentAt': cutoff.add(const Duration(hours: 2)).toIso8601String(),
        'offeredFulfilmentMethods': ['pickup'],
        'products': <Map<String, dynamic>>[],
      });
      return order.withCampaign(campaign);
    }

    expect(
      orderWithCutoff(
        DateTime.now().add(const Duration(hours: 1)),
      ).canCancelPreOrder,
      isTrue,
    );
    expect(
      orderWithCutoff(
        DateTime.now().subtract(const Duration(hours: 1)),
      ).canCancelPreOrder,
      isFalse,
    );
  });

  test('short cutoff uses weekday and local time', () {
    final cutoff = DateTime(2026, 8, 20, 20);
    expect(formatShortCutoff(cutoff), contains('By Thu'));
    expect(formatShortCutoff(cutoff), contains('8:00 PM'));
  });

  test('money formatting uses Indian rupee display', () {
    expect(formatMoney(8450), '₹8,450');
    expect(formatMoney(0), '₹0');
  });

  test('production heading changes from current demand to final quantity', () {
    final now = DateTime(2026, 8, 22, 10);
    expect(
      productionHeading(
        status: 'open',
        orderCutoffAt: now.add(const Duration(hours: 1)),
        now: now,
      ),
      'CURRENT DEMAND',
    );
    expect(
      productionHeading(status: 'open', orderCutoffAt: now, now: now),
      'FINAL QUANTITY TO PREPARE',
    );
    expect(
      productionHeading(
        status: 'closed',
        orderCutoffAt: now.add(const Duration(hours: 1)),
        now: now,
      ),
      'FINAL QUANTITY TO PREPARE',
    );
  });
}
