import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/home_screen.dart';
import 'package:societybites/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auth_provider': '2factor',
      'user_id': 'user-1',
      'society_id': 'society-1',
      'flat_id': 'flat-1',
    });
  });

  testWidgets('dead login asks the buyer to sign in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async {
            throw TokenExpiredException('Token expired');
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sign in again to load sellers.'), findsOneWidget);
    expect(
      find.text(
        'No listings yet. Be the first to add food from the seller dashboard.',
      ),
      findsNothing,
    );
  });

  testWidgets('missing authorization header asks the buyer to sign in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async {
            throw Exception('Missing or invalid Authorization header');
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sign in again to load sellers.'), findsOneWidget);
    expect(find.text('Unable to load sellers right now.'), findsNothing);
    expect(
      find.text(
        'No listings yet. Be the first to add food from the seller dashboard.',
      ),
      findsNothing,
    );
  });
}
