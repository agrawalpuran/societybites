import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter test harness can render a widget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('SocietyBites')),
      ),
    );

    expect(find.text('SocietyBites'), findsOneWidget);
  });
}
