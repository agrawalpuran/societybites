import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/admin/admin_incentives_screen.dart';
import 'package:societybites/screens/admin/admin_rule_builder.dart';
import 'package:societybites/services/incentive_api.dart';

void main() {
  testWidgets('rule builder adds a nested group and rejects an unknown field', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final node = RuleNode.group();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListView(
              children: [
                RuleBuilder(node: node, depth: 1, readOnly: false, onChanged: () => setState(() {})),
                Text(jsonEncode(node.toJson())),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add group'));
    await tester.pump();
    expect(node.conditions.any((child) => child.isGroup), isTrue);
    expect(find.textContaining('"combinator":"AND"'), findsOneWidget);

    final rejected = RuleNode.leaf();
    rejected.field = 'user.password';
    expect(validateRuleTree(rejected, 1), isNotNull);
  });

  IncentiveApi monitorApi() {
    return IncentiveApi(
      transport: (method, path, {body, query}) async {
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
        if (path == '/incentive/admin/campaigns') return [];
        if (path.endsWith('/referrals')) return {'referrals': []};
        if (path.endsWith('/rewards')) return {'rewards': []};
        if (path.endsWith('/overview')) return {};
        if (path.endsWith('/events')) {
          return {
            'events': [
              {'id': 'event-1', 'type': 'ORDER_QUALIFIED', 'status': 'FAILED', 'attempts': 2, 'lastError': 'budget', 'createdAt': '2026-11-17T00:00:00.000Z'},
            ],
          };
        }
        return {};
      },
    );
  }

  Future<void> openEvents(WidgetTester tester, {required bool superAdmin}) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: AdminIncentivesScreen(isSuperAdmin: superAdmin, api: monitorApi())));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Events'));
    await tester.pumpAndSettle();
  }

  testWidgets('portal admin can read a failed event and cannot replay it', (tester) async {
    await openEvents(tester, superAdmin: false);
    expect(find.textContaining('ORDER_QUALIFIED'), findsOneWidget);
    expect(find.textContaining('budget'), findsOneWidget);
    expect(find.text('Replay'), findsNothing);
    expect(find.textContaining('super admin'), findsOneWidget);
  });

  testWidgets('super admin can open replay for a failed event', (tester) async {
    await openEvents(tester, superAdmin: true);
    expect(find.text('Replay'), findsOneWidget);
  });
}
