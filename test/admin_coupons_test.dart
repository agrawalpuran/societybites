import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:societybites/models/coupon.dart';
import 'package:societybites/screens/admin/admin_coupons_screen.dart';

AdminCoupon sampleCoupon() {
  return AdminCoupon(
    id: 'c1',
    code: 'WELCOME100',
    name: 'Welcome offer',
    discountType: 'FIXED',
    discountValue: 100,
    minimumOrderValue: 300,
    validFrom: DateTime.utc(2026, 10, 5),
    validUntil: DateTime.utc(2026, 11, 4, 18, 29, 59),
    totalUsageLimit: 100,
    usagePerBuyerLimit: 1,
    usageFrequency: 'ONCE',
    campaignBudget: 10000,
    audienceType: 'ALL',
    status: 'ACTIVE',
    fundedBy: 'SOCIETYEATS',
    totalUsage: 0,
    appliedCount: 0,
    reversedCount: 0,
    amountUsed: 0,
    remainingBudget: 10000,
  );
}

void main() {
  test('coupon summary keeps the SocietyEats discount and usage', () {
    final coupon = AdminCoupon.fromJson({
      'id': 'c1',
      'code': 'WELCOME100',
      'name': 'Welcome offer',
      'discountType': 'FIXED',
      'discountValue': 100,
      'minimumOrderValue': 300,
      'validFrom': '2026-10-05T00:00:00.000Z',
      'validUntil': '2026-11-04T18:29:59.000Z',
      'totalUsageLimit': 100,
      'usagePerBuyerLimit': 1,
      'usageFrequency': 'ONCE',
      'campaignBudget': 10000,
      'audienceType': 'ALL',
      'status': 'ACTIVE',
      'fundedBy': 'SOCIETYEATS',
      'totalUsage': 2,
      'amountUsed': 200,
      'remainingBudget': 9800,
    });

    expect(coupon.discountLabel, '₹100 off');
    expect(coupon.amountUsed, 200);
    expect(coupon.remainingBudget, 9800);
    expect(coupon.fundedBy, 'SOCIETYEATS');
    expect(formatRupee(80.5), '₹80.50');
  });

  testWidgets('admin coupon list shows the offer and who pays it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminCouponsScreen(loadCoupons: () async => [sampleCoupon()]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WELCOME100 · ₹100 off'), findsOneWidget);
    expect(find.textContaining('Used 0 / 100'), findsOneWidget);
    expect(
      find.textContaining('SocietyEats pays the discount'),
      findsOneWidget,
    );
    expect(find.text('No coupons yet'), findsNothing);
  });

  testWidgets('empty coupon list explains there is nothing to manage', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminCouponsScreen(loadCoupons: () async => const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No coupons yet'), findsOneWidget);
    expect(find.text('New coupon'), findsOneWidget);
  });

  testWidgets('new coupon form requires a code before saving', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: AdminCouponEditorScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save coupon'));
    await tester.pump();

    expect(find.text('Enter a coupon code'), findsOneWidget);
  });
}
