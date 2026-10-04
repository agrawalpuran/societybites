import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/main.dart';
import 'package:societybites/screens/guest_landing_screen.dart';
import 'package:societybites/widgets/app_header.dart';
import 'package:societybites/widgets/screen_loading_note.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AuthGate shows loading then a visible screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          resolveStartScreen: () async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return const Scaffold(
              key: Key('startup-resolved'),
              body: Text('ready'),
            );
          },
        ),
      ),
    );

    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.byKey(const Key('home-feed-skeletons')), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('startup-resolved')), findsOneWidget);
    expect(find.text('ready'), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AuthGate does not restart session resolve on rebuild', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          resolveStartScreen: () async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 80));
            return const Scaffold(body: Text('ready'));
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    expect(calls, 1);
    expect(find.byKey(const Key('home-feed-skeletons')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AuthGate falls back to guest landing when session resolve throws',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            resolveStartScreen: () async {
              throw StateError('secure storage unavailable');
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(GuestLandingScreen), findsOneWidget);
      expect(find.byType(ScreenLoadingNote), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
