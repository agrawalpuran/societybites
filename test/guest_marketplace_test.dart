import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/guest_discovery.dart';
import 'package:societybites/screens/guest_kitchens_screen.dart';
import 'package:societybites/screens/guest_landing_screen.dart';
import 'package:societybites/screens/home_screen.dart';
import 'package:societybites/screens/seller_storefront_screen.dart';

void _ignoreKnownLayoutNoise() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Future<void> _scrollLanding(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
  await tester.pump();
}

Map<String, dynamic> _kitchenPayload() {
  return {
    'cityKey': 'bengaluru',
    'cityName': 'Bengaluru',
    'kitchens': [
      {
        'seller': {
          'id': 'seller-real',
          'name': 'Anita Sharma',
          'societyName': 'Prestige Notting Hill',
          'categories': ['Lunch'],
        },
        'listings': [
          {
            'id': 'listing-real',
            'name': 'Seed Biryani',
            'sellerId': 'seller-real',
            'sellerName': 'Anita Sharma',
            'price': 220,
            'quantity': 5,
            'status': 'active',
            'category': 'Lunch',
            'catalogType': 'REGULAR',
            'description': 'Home-style biryani',
          },
        ],
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hero marketing slides remain in GuestDiscovery', () {
    expect(GuestDiscovery.heroSlides, isNotEmpty);
    expect(GuestDiscovery.heroSlides.first.title, contains('Pappardelle'));
  });

  testWidgets('hero still shows marketing food titles on landing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GuestLandingScreen()));
    await tester.pump();
    expect(find.textContaining('Fresh Pappardelle'), findsWidgets);
    expect(find.text('Elena'), findsNothing);
  });

  testWidgets('Explore Menus opens kitchens list, not a sign-in wall', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GuestLandingScreen()));
    await tester.pump();
    await tester.tap(find.text('Explore Menus →'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(GuestKitchensScreen), findsOneWidget);
    expect(find.textContaining('Kitchens in'), findsOneWidget);
    expect(find.text('Discover homemade food near you'), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Elena'), findsNothing);
  });

  testWidgets('Explore All Kitchens opens kitchens list', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GuestLandingScreen()));
    await tester.pump();
    await _scrollLanding(tester);
    await tester.tap(find.text('Explore All Kitchens →'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GuestKitchensScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('Browse as Guest stays on landing (marketing explore)', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    await tester.pumpWidget(const MaterialApp(home: GuestLandingScreen()));
    await tester.pump();
    await tester.tap(find.text('Browse as Guest'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GuestLandingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('guest kitchens render real seller cards from API payload', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GuestKitchensScreen(fetchKitchens: () async => _kitchenPayload()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Kitchens in Bengaluru'), findsOneWidget);
    expect(find.text('Anita Sharma'), findsOneWidget);
    expect(find.text('Prestige Notting Hill'), findsOneWidget);
    expect(find.text('View Kitchen'), findsOneWidget);
    expect(find.text('Elena'), findsNothing);
    expect(find.text('km away'), findsNothing);
  });

  testWidgets('guest can open real kitchen storefront and REGULAR listings', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: GuestKitchensScreen(fetchKitchens: () async => _kitchenPayload()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('View Kitchen'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SellerStorefrontScreen), findsOneWidget);
    expect(find.text('Anita Sharma'), findsWidgets);
    expect(find.text('Seed Biryani'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('guest Add prompts login and does not add to cart', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          seller: const Seller(
            id: 'seller-real',
            name: 'Anita Sharma',
            block: 'Prestige Notting Hill',
            rating: 0,
            avatarIcon: Icons.restaurant,
            avatarColor: Color(0xFFD5E8D4),
          ),
          guestBrowse: true,
          guestSocietyName: 'Prestige Notting Hill',
          fetchListings: () async => [
            {
              'id': 'listing-real',
              'name': 'Seed Biryani',
              'sellerId': 'seller-real',
              'sellerName': 'Anita Sharma',
              'price': 220,
              'quantity': 5,
              'status': 'active',
              'catalogType': 'REGULAR',
            },
          ],
          fetchCampaigns: () async => const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Ready to order?'), findsOneWidget);
    expect(find.text('Sign In / Join Society'), findsOneWidget);
    expect(find.textContaining('•  ₹'), findsNothing);
  });

  testWidgets('HomeScreen still uses authenticated listings seam', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          fetchListings: () async => [
            {
              'id': 'real-1',
              'name': 'Seed Biryani',
              'sellerId': 'seller-seed',
              'sellerName': 'Anita Sharma',
              'price': 220,
              'quantity': 5,
              'status': 'active',
              'category': 'Lunch',
              'catalogType': 'REGULAR',
            },
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    while (tester.takeException() != null) {}

    expect(find.text('Anita Sharma'), findsWidgets);
    expect(find.text('Elena'), findsNothing);
  });
}
