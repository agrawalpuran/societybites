import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/admin/admin_incentives_screen.dart';
import 'package:societybites/services/incentive_api.dart';

void main() {
  IncentiveApi emptyApi({List<Map<String, dynamic>>? writes}) {
    final stored = {
      'master': false,
      'issuance': false,
      'redemption': false,
      'referral': false,
      'buyerReferral': false,
      'sellerReferral': false,
      'promotional': false,
    };
    Map<String, dynamic> payload() {
      final master = stored['master'] == true;
      final referral = master && stored['referral'] == true;
      return {
        'master': master,
        'issuance': master && stored['issuance'] == true,
        'redemption': master && stored['redemption'] == true,
        'referral': referral,
        'buyerReferral': referral && stored['buyerReferral'] == true,
        'sellerReferral': referral && stored['sellerReferral'] == true,
        'promotional': master && stored['promotional'] == true,
        'stored': Map<String, bool>.from(stored),
      };
    }
    return IncentiveApi(
      transport: (method, path, {body, query}) async {
        if (path == '/incentive/flags') return payload();
        if (path == '/incentive/admin/flags' && method == 'PUT') {
          final key = body is Map ? body['key']?.toString() : null;
          final enabled = body is Map && body['enabled'] == true;
          if (key != null && stored.containsKey(key)) stored[key] = enabled;
          writes?.add({'key': key, 'enabled': enabled});
          return payload();
        }
        if (path == '/incentive/admin/campaigns') return [];
        if (path.endsWith('/referrals')) return {'referrals': []};
        if (path.endsWith('/rewards')) return {'rewards': []};
        if (path.endsWith('/events')) return {'events': []};
        return {};
      },
    );
  }

  Future<void> pumpScreen(WidgetTester tester, {required bool superAdmin, IncentiveApi? api}) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminIncentivesScreen(isSuperAdmin: superAdmin, api: api ?? emptyApi()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('overview uses empty lists and hides writes for a portal admin', (tester) async {
    await pumpScreen(tester, superAdmin: false);
    expect(find.text('Incentives & Rewards'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('No incentive events yet.'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Campaigns'));
    await tester.pumpAndSettle();
    expect(find.text('Create campaign'), findsNothing);
    expect(find.text('No campaigns match this search.'), findsOneWidget);

    expect(find.widgetWithText(Tab, 'Settings'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('super admin confirms before changing a referral switch', (tester) async {
    final writes = <Map<String, dynamic>>[];
    await pumpScreen(tester, superAdmin: true, api: emptyApi(writes: writes));
    await tester.tap(find.widgetWithText(Tab, 'Campaigns'));
    await tester.pumpAndSettle();
    expect(find.text('Create campaign'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.text('These switches apply to new referral codes. Turning one off does not delete a code or a reward already stored.'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(4));
    expect(find.text('Master'), findsOneWidget);
    expect(find.text('Referral'), findsOneWidget);
    expect(find.text('Buyer referral'), findsOneWidget);
    expect(find.text('Seller referral'), findsOneWidget);
    expect(find.text('Off'), findsNWidgets(3));
    expect(tester.widgetList<Switch>(find.byType(Switch)).every((widget) => widget.value == false), isTrue);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Turn Referral on?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);

    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(writes, [
      {'key': 'referral', 'enabled': true},
    ]);
    expect(find.text('Saved, but off until Master is on.'), findsOneWidget);
  });
}
