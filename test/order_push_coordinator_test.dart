import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/services/order_push_coordinator.dart';

Order _order({required String id, String status = 'ready'}) {
  return Order(
    id: id,
    orderId: 'ORD-1',
    items: const [],
    date: 'Today',
    status: status,
    statusStep: orderStatusStepFor(status),
    orderTotal: 100,
    subtotal: 100,
    communityFee: 0,
  );
}

void main() {
  test('order_completed hint advances status immediately', () {
    final order = _order(id: 'o1', status: 'ready');
    final updated = applyOrderPushHint(
      order,
      const OrderPushHint(orderId: 'o1', status: 'completed'),
    );
    expect(updated.status, 'completed');
    expect(updated.statusStep, 3);
    expect(updated.completedAt, isNotNull);
  });

  test('applyOrderPushHints promotes accepted before list refresh catches up', () {
    final merged = applyOrderPushHints(
      [_order(id: 'o1', status: 'pending')],
      [const OrderPushHint(orderId: 'o1', status: 'accepted')],
    );
    expect(merged.single.status, 'accepted');
  });

  test('hint from notification type when status field missing', () {
    final hint = OrderPushHint.fromMessageData({
      'orderId': 'o2',
      'notificationType': 'order_completed',
    });
    expect(hint?.status, 'completed');
  });

  test('mergeStatusPatch keeps line items from prior order', () {
    const prior = Order(
      id: 'o4',
      orderId: 'SE-1',
      items: [
        OrderLineItem(
          quantity: 2,
          unitPrice: 50,
          food: FoodItem(
            id: 'f1',
            name: 'Samosa',
            sellerId: 's1',
            sellerName: 'Chef',
            block: 'A',
            price: 50,
            rating: 4,
            pickupTime: '10m',
            description: '',
            icon: Icons.restaurant,
            bgColor: Color(0xFFF0F2F1),
          ),
        ),
      ],
      date: 'Today',
      status: 'accepted',
      statusStep: 1,
      orderTotal: 100,
      subtotal: 100,
      communityFee: 0,
    );
    final merged = Order.mergeStatusPatch(prior, {
      'statusPatch': true,
      'status': 'ready',
      'statusStep': 2,
    });
    expect(merged.status, 'ready');
    expect(merged.items, prior.items);
    expect(merged.orderTotal, 100);
  });

  test('mergeStatusPatch applies payment and ready-by fields', () {
    const prior = Order(
      id: 'o5',
      orderId: 'SE-2',
      items: const [],
      date: 'Today',
      status: 'accepted',
      statusStep: 1,
      orderTotal: 50,
      subtotal: 50,
      communityFee: 0,
      paymentStatus: 'buyer_marked_paid',
    );
    final readyBy = DateTime.utc(2026, 10, 8, 10, 30);
    final merged = Order.mergeStatusPatch(prior, {
      'statusPatch': true,
      'paymentStatus': 'seller_confirmed',
      'expectedReadyAt': readyBy.toIso8601String(),
    });
    expect(merged.paymentStatus, 'seller_confirmed');
    expect(merged.expectedReadyAt, readyBy);
  });

  test('order_created yields hint for kitchen prefetch', () {
    final hint = OrderPushHint.fromMessageData({
      'orderId': 'o3',
      'notificationType': 'order_created',
      'status': 'accepted',
    });
    expect(hint?.orderId, 'o3');
    expect(hint?.status, 'accepted');
  });
}
