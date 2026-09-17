import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/guest_landing_screen.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/services/session_service.dart';

void _ignoreKnownLayoutNoise() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('Incorrect use of ParentDataWidget') ||
        text.contains('ListTile background color')) {
      return;
    }
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Map<String, dynamic> _buyerMe() {
  return {
    'id': 'buyer-1',
    'name': 'Priya',
    'phone': '+919845154070',
    'role': 'buyer',
    'society': {'name': 'Prestige Notting Hill'},
    'flat': {'flatNumber': '101'},
  };
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  Future<void> Function()? deleteAccount,
  Map<String, dynamic>? profile,
}) async {
      SharedPreferences.setMockInitialValues({
    'user_id': 'buyer-1',
    'user_role': 'buyer',
    'user_name': 'Priya',
    'phone': '+919845154070',
    'auth_provider': '2factor',
  });
  // Seed in-memory session token used by SessionService.isSignedIn / getToken.
  await SessionService.saveToken('test-token');
  await tester.binding.setSurfaceSize(const Size(800, 2800));
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        fetchProfile: () async => profile ?? _buyerMe(),
        deleteAccount: deleteAccount,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  while (tester.takeException() != null) {}
}

Future<void> _scrollToDelete(WidgetTester tester) async {
  final list = find.byType(ListView);
  expect(list, findsWidgets);
  await tester.drag(list.first, const Offset(0, -1200));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _ignoreKnownLayoutNoise();
  });

  testWidgets('Delete Account appears for authenticated profile users', (
    tester,
  ) async {
    await _pumpProfile(tester, deleteAccount: () async {});
    await _scrollToDelete(tester);
    expect(find.text('Delete Account'), findsOneWidget);
    expect(find.text('ACCOUNT & SECURITY'), findsOneWidget);
    expect(
      find.textContaining('Permanently delete your SocietyBites account'),
      findsOneWidget,
    );
  });

  testWidgets('guest landing does not show Delete Account', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: GuestLandingScreen()));
    await tester.pump();
    expect(find.text('Delete Account'), findsNothing);
    expect(find.text('ACCOUNT & SECURITY'), findsNothing);
  });

  testWidgets('Delete Account shows confirmation dialog', (tester) async {
    var deleted = false;
    await _pumpProfile(
      tester,
      deleteAccount: () async {
        deleted = true;
      },
    );
    await _scrollToDelete(tester);
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();

    expect(find.text('Delete your account?'), findsOneWidget);
    expect(
      find.textContaining('permanently deleted'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(deleted, isFalse);
  });

  testWidgets('Cancel leaves account and session intact', (tester) async {
    var deleted = false;
    await _pumpProfile(
      tester,
      deleteAccount: () async {
        deleted = true;
      },
    );
    await _scrollToDelete(tester);
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deleted, isFalse);
    expect(await SessionService.getUserId(), 'buyer-1');
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(GuestLandingScreen), findsNothing);
  });

  testWidgets('failed deletion keeps session and stays on profile', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      deleteAccount: () async {
        throw Exception('Deletion failed');
      },
    );
    await _scrollToDelete(tester);
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, 'Delete Account'),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Deletion failed'), findsOneWidget);
    expect(await SessionService.getUserId(), 'buyer-1');
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(GuestLandingScreen), findsNothing);
  });

  testWidgets(
    'successful deletion clears session and opens GuestLandingScreen',
    (tester) async {
      var deleteCalls = 0;
      await _pumpProfile(
        tester,
        deleteAccount: () async {
          deleteCalls += 1;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
      );
      await _scrollToDelete(tester);
      await tester.tap(find.text('Delete Account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Delete your account?'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(TextButton, 'Delete Account'),
      );
      await tester.pump(); // start delete
      expect(find.textContaining('Deleting your account'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(deleteCalls, 1);
      expect(await SessionService.getUserId(), isNull);
      expect(await SessionService.getToken(), isNull);
      expect(find.byType(GuestLandingScreen), findsOneWidget);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    },
  );
}
