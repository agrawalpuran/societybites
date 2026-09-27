import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/widgets/upi_app_brand_icon.dart';

void main() {
  testWidgets('renders brand marks for each UPI app', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              UpiAppBrandIcon(appId: 'gpay'),
              UpiAppBrandIcon(appId: 'phonepe'),
              UpiAppBrandIcon(appId: 'paytm'),
              UpiAppBrandIcon(appId: 'bhim'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(UpiAppBrandIcon), findsNWidgets(4));
  });
}
