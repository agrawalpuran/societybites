import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:societybites/models/issue_report.dart';
import 'package:societybites/screens/my_reports_screen.dart';
import 'package:societybites/screens/report_issue_screen.dart';

void main() {
  testWidgets('empty My Reports state explains where issues appear', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: IssueReportsEmptyState())),
    );

    expect(find.text('No reports yet'), findsOneWidget);
    expect(
      find.text('Any issues or feedback you submit will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('report form asks for a category before submitting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReportIssueScreen(loadReports: () async => const []),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How can we help?'), findsWidgets);
    expect(find.text('Payment / UPI'), findsOneWidget);
    await tester.tap(find.text('Submit Report'));
    await tester.pump();
    expect(find.text('Choose a category'), findsOneWidget);
  });

  test('issue cards keep a short description and a readable date', () {
    final report = IssueReport.fromJson({
      'id': '1',
      'reference': 'SE-1024',
      'userRole': 'buyer',
      'category': 'PAYMENT_UPI',
      'description': 'Payment failed after scanning QR',
      'status': 'UNDER_REVIEW',
      'createdAt': '2026-10-05T06:30:00.000Z',
      'orderId': 'SB-548969',
    });

    expect(report.categoryLabel, 'Payment / UPI');
    expect(report.statusLabel, 'Under Review');
    expect(report.orderId, 'SB-548969');
    expect(report.shortDescription, 'Payment failed after scanning QR');
  });
}
