import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/home_screen.dart';
import 'package:societybites/screens/my_listings_screen.dart';
import 'package:societybites/screens/preorder_detail_screen.dart';
import 'package:societybites/screens/profile_screen.dart';
import 'package:societybites/screens/seller_feedback_screen.dart';
import 'package:societybites/screens/seller_preorders_screen.dart';
import 'package:societybites/screens/seller_storefront_screen.dart';
import 'package:societybites/services/my_listings_cache.dart';

Map<String, dynamic> _listingJson(String name) {
  return {
    'id': 'listing-$name',
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 100,
    'status': 'active',
  };
}

Map<String, dynamic> _campaignJson(String title) {
  final now = DateTime.now();
  return {
    'id': 'campaign-1',
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'title': title,
    'status': 'open',
    'orderOpenAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
    'orderCutoffAt': now.add(const Duration(hours: 5)).toIso8601String(),
    'fulfilmentAt': now.add(const Duration(days: 1)).toIso8601String(),
    'products': [
      {
        'listingId': 'listing-1',
        'name': 'Samosa',
        'sellerId': 'seller-1',
        'price': 20,
      },
    ],
  };
}

const _seller = Seller(
  id: 'seller-1',
  name: 'Anita',
  block: 'A',
  rating: 5,
  avatarIcon: Icons.restaurant,
  avatarColor: Color(0xFFE8F5EE),
);

void _ignoreKnownLayoutNoise() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed') ||
        text.contains('ListTile background color')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SellerStorefrontMemoryCache.clear();
    MyListingsCache.clear();
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'user_name': 'Cached Neighbor',
      'phone': '9999999999',
      'society_name': 'Green Heights',
    });
  });

  testWidgets('Home first load can show a spinner then listings', (tester) async {
    _ignoreKnownLayoutNoise();
    final pending = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(fetchListings: () => pending.future),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    pending.complete([_listingJson('Paneer Wrap')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Paneer Wrap'), findsOneWidget);
  });

  testWidgets('Home refresh keeps listings visible and replaces on success', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    var calls = 0;
    final hang = Completer<List<Map<String, dynamic>>>();
    final key = GlobalKey<HomeScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          key: key,
          fetchListings: () {
            calls++;
            if (calls == 1) {
              return Future.value([_listingJson('Old Dal')]);
            }
            if (calls == 2) return hang.future;
            return Future.value([_listingJson('New Dal')]);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Old Dal'), findsOneWidget);

    key.currentState!.refresh();
    await tester.pump();
    expect(find.text('Old Dal'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    hang.complete([_listingJson('New Dal')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('New Dal'), findsOneWidget);
    expect(find.text('Old Dal'), findsNothing);
  });

  testWidgets('Home failed refresh keeps existing listings', (tester) async {
    _ignoreKnownLayoutNoise();
    var calls = 0;
    final key = GlobalKey<HomeScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          key: key,
          fetchListings: () async {
            calls++;
            if (calls == 1) return [_listingJson('Kept Khichdi')];
            throw Exception('home refresh failed');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Kept Khichdi'), findsOneWidget);

    key.currentState!.refresh();
    await tester.pump();
    await tester.pump();

    expect(find.text('Kept Khichdi'), findsOneWidget);
    expect(find.textContaining('home refresh failed'), findsNothing);
  });

  testWidgets('Profile first load shows chrome then keeps data on refresh', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    SharedPreferences.setMockInitialValues({
      'user_id': 'user-1',
      'user_name': 'Cached Neighbor',
    });
    var calls = 0;
    final first = Completer<Map<String, dynamic>>();
    final hang = Completer<Map<String, dynamic>>();
    final key = GlobalKey<ProfileScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          key: key,
          fetchProfile: () {
            calls++;
            if (calls == 1) return first.future;
            return hang.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Cached Neighbor'), findsOneWidget);

    first.complete({'name': 'Visible Neighbor'});
    await tester.pump();
    await tester.pump();
    expect(find.text('Visible Neighbor'), findsOneWidget);

    unawaited(key.currentState!.reload());
    await tester.pump();
    expect(find.text('Visible Neighbor'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    hang.complete({'name': 'Visible Neighbor'});
    await tester.pump();
  });

  testWidgets('My Listings first-load failure shows retry, not a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => throw Exception('listings unavailable'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('listings unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('My Listings still renders when one listing is corrupt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [
            _listingJson('Good Pasta'),
            {'name': 'Broken', 'price': 10},
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Good Pasta'), findsOneWidget);
  });

  testWidgets('My Listings second open shows cache without a spinner', (
    tester,
  ) async {
    var calls = 0;
    final hang = Completer<List<Map<String, dynamic>>>();
    Future<List<Map<String, dynamic>>> fetch() {
      calls++;
      if (calls == 1) {
        return Future.value([_listingJson('Cached Pasta')]);
      }
      return hang.future;
    }

    await tester.pumpWidget(
      MaterialApp(home: MyListingsScreen(fetchListings: fetch)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Cached Pasta'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(home: MyListingsScreen(fetchListings: fetch)),
    );
    await tester.pump();
    expect(find.text('Cached Pasta'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    hang.complete([_listingJson('Cached Pasta')]);
    await tester.pump();
  });

  testWidgets('My Listings refresh keeps existing content', (tester) async {
    var calls = 0;
    final hang = Completer<List<Map<String, dynamic>>>();
    final key = GlobalKey<MyListingsScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          key: key,
          fetchListings: () {
            calls++;
            if (calls == 1) {
              return Future.value([_listingJson('My Pasta')]);
            }
            if (calls == 2) return hang.future;
            throw Exception('listings refresh failed');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('My Pasta'), findsOneWidget);

    key.currentState!.reload();
    await tester.pump();
    expect(find.text('My Pasta'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    hang.completeError(Exception('listings refresh failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('My Pasta'), findsOneWidget);
  });

  testWidgets('Storefront refresh keeps existing content', (tester) async {
    var calls = 0;
    final hang = Completer<List<Map<String, dynamic>>>();
    final key = GlobalKey<SellerStorefrontScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: SellerStorefrontScreen(
          key: key,
          seller: _seller,
          fetchListings: () {
            calls++;
            if (calls == 1) {
              return Future.value([_listingJson('Storefront Idli')]);
            }
            return hang.future;
          },
          fetchCampaigns: () async => [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Storefront Idli'), findsOneWidget);

    key.currentState!.reload();
    await tester.pump();
    expect(find.text('Storefront Idli'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    hang.completeError(Exception('storefront refresh failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Storefront Idli'), findsOneWidget);
  });

  testWidgets('Seller preorder list refresh keeps existing content', (
    tester,
  ) async {
    var calls = 0;
    final hang = Completer<List<Map<String, dynamic>>>();
    final key = GlobalKey<SellerPreOrdersScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: SellerPreOrdersScreen(
          key: key,
          fetchCampaigns: () {
            calls++;
            if (calls == 1) {
              return Future.value([_campaignJson('Weekend Thali')]);
            }
            return hang.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Weekend Thali'), findsOneWidget);

    key.currentState!.reload();
    await tester.pump();
    expect(find.text('Weekend Thali'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    hang.completeError(Exception('preorder refresh failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Weekend Thali'), findsOneWidget);
  });

  testWidgets('Seller preorder detail refresh keeps existing content', (
    tester,
  ) async {
    var calls = 0;
    final hang = Completer<Map<String, dynamic>>();
    final key = GlobalKey<PreOrderDetailScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: PreOrderDetailScreen(
          key: key,
          campaignId: 'campaign-1',
          fetchCampaign: () {
            calls++;
            if (calls == 1) {
              return Future.value(_campaignJson('Detail Thali'));
            }
            return hang.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Detail Thali'), findsOneWidget);

    key.currentState!.reload();
    await tester.pump();
    expect(find.text('Detail Thali'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    hang.completeError(Exception('detail refresh failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Detail Thali'), findsOneWidget);
  });

  testWidgets('Seller feedback refresh keeps existing content', (tester) async {
    var calls = 0;
    final hang = Completer<List<Map<String, dynamic>>>();
    final key = GlobalKey<SellerFeedbackScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: SellerFeedbackScreen(
          key: key,
          fetchReviews: () {
            calls++;
            if (calls == 1) {
              return Future.value([
                {
                  'name': 'Neighbor',
                  'rating': 5,
                  'comment': 'Loved the dal',
                },
              ]);
            }
            return hang.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Loved the dal'), findsOneWidget);

    key.currentState!.reload();
    await tester.pump();
    expect(find.text('Loved the dal'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    hang.completeError(Exception('feedback refresh failed'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Loved the dal'), findsOneWidget);
  });
}
