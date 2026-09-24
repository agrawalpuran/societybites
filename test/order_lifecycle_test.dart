import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/widgets/order_lifecycle_dialogs.dart';

void main() {
  test('seller sees Accept + Reject for PENDING', () {
    final life = SellerOrderLifecycle.forStatus('pending');
    expect(life.showAccept, isTrue);
    expect(life.showReject, isTrue);
    expect(life.primaryLabel, 'Accept Order');
    expect(life.showMarkReady, isFalse);
    expect(life.showComplete, isFalse);
  });

  test('seller sees Mark Ready for ACCEPTED', () {
    final life = SellerOrderLifecycle.forStatus('accepted');
    expect(life.showMarkReady, isTrue);
    expect(life.primaryLabel, 'Mark Ready');
    expect(life.showAccept, isFalse);
    expect(life.showReject, isFalse);
    expect(life.headline, 'Order Accepted');
  });

  test('seller sees Complete for READY', () {
    final life = SellerOrderLifecycle.forStatus('ready');
    expect(life.showComplete, isTrue);
    expect(life.primaryLabel, 'Complete Order');
    expect(life.showMarkReady, isFalse);
    expect(life.showReject, isFalse);
  });

  test('completed order has no action', () {
    final life = SellerOrderLifecycle.forStatus('completed');
    expect(life.hasPrimaryAction, isFalse);
    expect(life.showReject, isFalse);
  });

  test('rejected order has no action', () {
    final life = SellerOrderLifecycle.forStatus('rejected');
    expect(life.hasPrimaryAction, isFalse);
    expect(life.showReject, isFalse);
  });

  test('preparing action does not exist', () {
    for (final status in [
      'pending',
      'accepted',
      'ready',
      'completed',
      'rejected',
    ]) {
      expect(
        SellerOrderLifecycle.forStatus(status).primaryLabel,
        isNot('Start Preparing'),
      );
    }
  });

  test('pickup action does not exist', () {
    for (final status in [
      'pending',
      'accepted',
      'ready',
      'completed',
      'rejected',
    ]) {
      expect(
        SellerOrderLifecycle.forStatus(status).primaryLabel,
        isNot('Mark Pickup'),
      );
    }
  });

  test('buyer progress steps follow order.status only', () {
    expect(BuyerOrderLifecycle.progressStep('pending'), 0);
    expect(BuyerOrderLifecycle.progressStep('accepted'), 1);
    expect(BuyerOrderLifecycle.progressStep('preparing'), 1);
    expect(BuyerOrderLifecycle.progressStep('ready'), 2);
    expect(BuyerOrderLifecycle.progressStep('picked_up'), 2);
    expect(BuyerOrderLifecycle.progressStep('completed'), 3);
    expect(BuyerOrderLifecycle.progressStep('rejected'), -1);
    expect(BuyerOrderLifecycle.progressStep('cancelled'), -1);
  });

  test('seller_confirmed payment does not change lifecycle step', () {
    expect(BuyerOrderLifecycle.progressStep('accepted'), 1);
    expect(BuyerOrderLifecycle.progressStep('preparing'), 1);
    expect(BuyerOrderLifecycle.headline('accepted'), 'Order confirmed');
    expect(BuyerOrderLifecycle.headline('preparing'), 'Order confirmed');
    expect(
      BuyerOrderLifecycle.detail('accepted'),
      isNot('Please collect your order from the seller.'),
    );
  });

  test('legacy preparing + seller_confirmed is Confirmed, seller Mark Ready', () {
    expect(BuyerOrderLifecycle.progressStep('preparing'), 1);
    expect(BuyerOrderLifecycle.headline('preparing'), 'Order confirmed');
    final seller = SellerOrderLifecycle.forStatus('preparing');
    expect(seller.primaryLabel, 'Mark Ready');
    expect(seller.showComplete, isFalse);
  });

  test('Mark Ready tries ready first, then legacy preparing path', () {
    expect(markReadyStatusPaths('accepted'), [
      ['ready'],
      ['preparing', 'ready'],
    ]);
    expect(markReadyStatusPaths('preparing'), [
      ['ready'],
    ]);
  });

  test('buyer sees Confirmed after acceptance', () {
    expect(BuyerOrderLifecycle.headline('accepted'), 'Order confirmed');
    expect(
      BuyerOrderLifecycle.detail('accepted'),
      'Your order is being prepared.',
    );
    expect(BuyerOrderLifecycle.progressStep('accepted'), 1);
  });

  test('buyer sees Ready for Pickup after READY', () {
    expect(BuyerOrderLifecycle.headline('ready'), 'Ready for Pickup');
    expect(
      BuyerOrderLifecycle.detail('ready'),
      'Please collect your order from the seller.',
    );
    expect(BuyerOrderLifecycle.progressStep('ready'), 2);
  });

  test('buyer sees Completed after completion', () {
    expect(BuyerOrderLifecycle.headline('completed'), 'Order completed');
    expect(BuyerOrderLifecycle.progressStep('completed'), 3);
  });

  test('buyer sees Rejected after rejection', () {
    expect(BuyerOrderLifecycle.headline('rejected'), 'Order rejected');
    expect(
      BuyerOrderLifecycle.detail('rejected'),
      'Unfortunately, the seller could not fulfil this order.',
    );
  });

  test('buyer cancel is allowed only before UPI I\'ve Paid or COD accept', () {
    expect(
      BuyerOrderLifecycle.canCancel(
        status: 'pending',
        paymentStatus: 'pending',
        paymentMethod: 'upi',
      ),
      isTrue,
    );
    expect(
      BuyerOrderLifecycle.canCancel(
        status: 'accepted',
        paymentStatus: 'pending',
        paymentMethod: 'upi',
      ),
      isTrue,
    );
    expect(
      BuyerOrderLifecycle.canCancel(
        status: 'accepted',
        paymentStatus: 'buyer_marked_paid',
        paymentMethod: 'upi',
      ),
      isFalse,
    );
    expect(
      BuyerOrderLifecycle.canCancel(
        status: 'accepted',
        paymentStatus: 'seller_confirmed',
        paymentMethod: 'upi',
      ),
      isFalse,
    );
    expect(
      BuyerOrderLifecycle.canCancel(
        status: 'pending',
        paymentStatus: 'pending',
        paymentMethod: 'cash',
      ),
      isTrue,
    );
    expect(
      BuyerOrderLifecycle.canCancel(
        status: 'accepted',
        paymentStatus: 'pending',
        paymentMethod: 'cash',
      ),
      isFalse,
    );
    expect(
      BuyerOrderLifecycle.canCancel(
        status: 'ready',
        paymentStatus: 'pending',
        paymentMethod: 'upi',
      ),
      isFalse,
    );
  });

  test('buyer does not need to perform lifecycle actions', () {
    for (final status in [
      'pending',
      'accepted',
      'ready',
      'completed',
      'rejected',
    ]) {
      expect(BuyerOrderLifecycle.hasProgressAction(status), isFalse);
    }
  });

  test('buyer terminal orders stay active for 24 hours then move to past', () {
    final now = DateTime.utc(2026, 9, 25, 10, 30);
    expect(
      BuyerOrderVisibility.isInBuyerActiveTab(
        status: 'accepted',
        now: now,
      ),
      isTrue,
    );
    expect(
      BuyerOrderVisibility.isInBuyerActiveTab(
        status: 'completed',
        completedAt: now.subtract(const Duration(hours: 3)),
        now: now,
      ),
      isTrue,
    );
    expect(
      BuyerOrderVisibility.isInBuyerActiveTab(
        status: 'completed',
        completedAt: now.subtract(const Duration(hours: 24)),
        now: now,
      ),
      isFalse,
    );
    expect(
      BuyerOrderVisibility.isInBuyerActiveTab(
        status: 'rejected',
        rejectedAt: now.subtract(const Duration(hours: 5)),
        now: now,
      ),
      isTrue,
    );
    expect(
      BuyerOrderVisibility.isInBuyerActiveTab(
        status: 'cancelled',
        cancelledAt: now.subtract(const Duration(hours: 48)),
        now: now,
      ),
      isFalse,
    );
    expect(
      BuyerOrderVisibility.isInBuyerActiveTab(status: 'completed', now: now),
      isFalse,
    );
  });

  test('reject reason splits optional seller note', () {
    expect(
      BuyerOrderVisibility.rejectReasonLabel('Ingredients unavailable\nSold out'),
      'Ingredients unavailable',
    );
    expect(
      BuyerOrderVisibility.rejectNote('Ingredients unavailable\nSold out'),
      'Sold out',
    );
    expect(BuyerOrderVisibility.rejectNote('Ingredients unavailable'), isNull);
  });

  testWidgets('reject confirmation works', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RejectOrderResult? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                captured = await confirmRejectOrder(context);
              },
              child: const Text('Open reject'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject Order?'), findsOneWidget);
    expect(find.text("Why can't you fulfil this order?"), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reject Order?'), findsNothing);

    await tester.tap(find.text('Open reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingredients unavailable'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reject-order-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Reject Order?'), findsNothing);
    expect(captured?.reason, 'Ingredients unavailable');
    expect(captured?.note, isNull);
  });

  testWidgets('complete confirmation works', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => confirmCompleteOrder(context),
              child: const Text('Open complete'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open complete'));
    await tester.pumpAndSettle();

    expect(find.text('Complete this order?'), findsOneWidget);
    expect(
      find.text(
        'Please confirm that the food has been handed over to the buyer.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Complete Order'));
    await tester.pumpAndSettle();
    expect(find.text('Complete this order?'), findsNothing);
  });
}
