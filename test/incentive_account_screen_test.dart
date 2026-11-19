import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/incentive/incentive_account_screen.dart';
import 'package:societybites/services/incentive_api.dart';

void main() {
  testWidgets('account screen shows the caller rewards and non-cash balances', (tester) async {
    final api = IncentiveApi(
      transport: (method, path, {body, query}) async {
        expect(query == null || !query.containsKey('userId'), true);
        expect(query == null || !query.containsKey('recipientUserId'), true);
        if (path == '/incentive/flags') {
          return {
            'master': false,
            'issuance': false,
            'redemption': false,
            'referral': false,
            'buyerReferral': false,
            'sellerReferral': false,
            'promotional': false,
          };
        }
        if (path == '/incentive/rewards') {
          return {
            'rewards': [
              {'rewardType': 'FIXED_COUPON', 'status': 'ISSUED', 'amount': '25.00', 'currency': 'INR'},
              {'rewardType': 'PROMOTIONAL_CREDIT', 'status': 'ISSUED', 'amount': '10.00', 'currency': 'INR'},
              {'rewardType': 'POINTS', 'status': 'ISSUED', 'amount': '5.00', 'currency': 'INR'},
            ],
            'balances': {'promotionalCredit': '6.00', 'points': '5.00'},
          };
        }
        if (path == '/incentive/rewards/history') {
          return {
            'entries': [
              {'entryType': 'ISSUE', 'amount': '10.00', 'rewardType': 'PROMOTIONAL_CREDIT', 'createdAt': '2026-11-17T10:00:00.000Z', 'idempotencyKey': 'issue-a'},
            ],
          };
        }
        return {};
      },
    );

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: IncentiveAccountScreen(audience: 'BUYER', api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Referral codes are switched off'), findsOneWidget);
    expect(find.textContaining('Fixed coupon'), findsOneWidget);
    expect(find.textContaining('Promotional credit'), findsWidgets);
    expect(find.text('6.00'), findsOneWidget);
    expect(find.textContaining('cannot be withdrawn'), findsWidgets);
    expect(find.textContaining('only after SocietyEats confirms it'), findsOneWidget);
    expect(find.textContaining('Incentive offers are off'), findsOneWidget);
    expect(find.textContaining('issue-a'), findsOneWidget);
  });
}
