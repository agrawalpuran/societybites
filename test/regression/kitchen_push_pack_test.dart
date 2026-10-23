import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/services/order_push_coordinator.dart';

void main() {
  test('order_created hint is a kitchen target and starts pending', () {
    final hint = OrderPushHint.fromMessageData({
      'orderId': 'ord-new',
      'notificationType': 'order_created',
      'orderNumber': 'SE-100010',
    });
    expect(hint, isNotNull);
    expect(hint!.orderId, 'ord-new');
    expect(hint.status, 'pending');
    expect(orderPushHintTargetsSellerKitchen(hint), isTrue);
  });

  test('completed lifecycle badge must not fall back to ACTIVE', () {
    expect(SellerOrderLifecycle.forStatus('completed').badge, 'COMPLETED');
  });
}
