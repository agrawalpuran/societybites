import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/add_listing_screen.dart';
import 'package:societybites/screens/create_preorder_screen.dart';
import 'package:societybites/screens/my_listings_screen.dart';
import 'package:societybites/services/my_listings_cache.dart';

Map<String, dynamic> _listingJson(
  String name, {
  String catalogType = listingCatalogRegular,
  String id = '',
}) {
  return {
    'id': id.isEmpty ? 'listing-$name' : id,
    'name': name,
    'sellerId': 'seller-1',
    'sellerName': 'Anita',
    'price': 100,
    'status': 'active',
    'catalogType': catalogType,
  };
}

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
    MyListingsCache.clear();
    SharedPreferences.setMockInitialValues({
      'user_id': 'seller-1',
      'user_name': 'Anita',
      'phone': '9999999999',
      'society_name': 'Green Heights',
    });
  });

  testWidgets('My Listings shows All, Regular, Made to Order, and Pre-orders tabs', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [
            _listingJson('Samosa'),
            _listingJson(
              'Sunday Biryani',
              catalogType: listingCatalogPreorder,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('All'), findsWidgets);
    expect(find.textContaining('Regular'), findsWidgets);
    expect(find.textContaining('Made to Order'), findsWidgets);
    expect(find.textContaining('Pre-orders'), findsWidgets);
    expect(find.text('Samosa'), findsOneWidget);
    expect(find.text('Sunday Biryani'), findsOneWidget);

    await tester.tap(find.textContaining('Regular (').first);
    await tester.pumpAndSettle();
    expect(find.text('Samosa'), findsOneWidget);
    expect(find.text('Sunday Biryani'), findsNothing);

    await tester.tap(find.textContaining('Pre-orders (').first);
    await tester.pumpAndSettle();

    expect(find.text('Sunday Biryani'), findsOneWidget);
    expect(find.text('Samosa'), findsNothing);
    expect(find.text('Add Pre-order Item'), findsWidgets);
  });

  testWidgets('Add Listing copy depends on catalog', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AddListingScreen()),
    );
    await tester.pump();
    expect(find.text('List a New Bite'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: AddListingScreen(catalogType: listingCatalogPreorder),
      ),
    );
    await tester.pump();
    expect(find.text('Add a pre-order item'), findsOneWidget);
  });

  testWidgets('Add Listing photo picker offers camera and gallery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AddListingScreen()),
    );
    await tester.pump();

    await tester.tap(find.text('Upload Cover Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Add Food Photo'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Add Food Photo'), findsNothing);
  });

  testWidgets('Move Regular to Pre-orders shows confirmation and updates tabs', (
    tester,
  ) async {
    _ignoreKnownLayoutNoise();
    var catalogType = listingCatalogRegular;
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [
            _listingJson('Samosa', catalogType: catalogType, id: 'samosa-1'),
          ],
          updateCatalog: (listingId, nextType) async {
            expect(listingId, 'samosa-1');
            catalogType = nextType;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Move to Pre-orders'));
    await tester.pumpAndSettle();
    expect(find.text('Move Samosa to Pre-orders?'), findsOneWidget);
    expect(
      find.textContaining('no longer be available for regular orders'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Samosa'), findsOneWidget);

    await tester.tap(find.text('Move to Pre-orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Regular (').first);
    await tester.pumpAndSettle();
    expect(find.text('No regular listings yet'), findsOneWidget);

    await tester.tap(find.textContaining('Pre-orders').first);
    await tester.pumpAndSettle();
    expect(find.text('Samosa'), findsOneWidget);
    expect(find.text('Move to Regular Orders'), findsOneWidget);
  });

  testWidgets('Move Pre-orders to Regular updates UI', (tester) async {
    _ignoreKnownLayoutNoise();
    var catalogType = listingCatalogPreorder;
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [
            _listingJson(
              'Sunday Biryani',
              catalogType: catalogType,
              id: 'biryani-1',
            ),
          ],
          updateCatalog: (listingId, nextType) async {
            expect(listingId, 'biryani-1');
            catalogType = nextType;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.textContaining('Pre-orders').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Regular Orders'));
    await tester.pumpAndSettle();
    expect(find.text('Move Sunday Biryani to Regular Orders?'), findsOneWidget);
    expect(
      find.textContaining('available for normal daily ordering'),
      findsOneWidget,
    );
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();

    expect(find.text('No pre-order items yet'), findsOneWidget);
    await tester.tap(find.textContaining('Regular (').first);
    await tester.pumpAndSettle();
    expect(find.text('Sunday Biryani'), findsOneWidget);
  });

  testWidgets('My Listings actions stay separate on a compact card width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 640,
            child: MyListingsScreen(
              fetchListings: () async => [_listingJson('Samosa')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Move to Pre-orders'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Active campaign restriction is shown', (tester) async {
    _ignoreKnownLayoutNoise();
    await tester.pumpWidget(
      MaterialApp(
        home: MyListingsScreen(
          fetchListings: () async => [
            _listingJson('Samosa', id: 'samosa-1'),
          ],
          updateCatalog: (listingId, catalogType) async {
            throw Exception(
              'This item is part of an active pre-order campaign and cannot be moved until the campaign is completed.',
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Move to Pre-orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('active pre-order campaign'),
      findsOneWidget,
    );
  });

  testWidgets('Pre-order campaign picker only shows PREORDER listings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddPreOrderProductScreen(
          campaignId: 'campaign-1',
          existingProductNames: const {},
          fetchListings: () async => [
            _listingJson('Aloo Paratha'),
            _listingJson(
              'Friday Special Biryani',
              catalogType: listingCatalogPreorder,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<FoodItem>));
    await tester.pumpAndSettle();

    expect(find.text('Friday Special Biryani'), findsWidgets);
    expect(find.text('Aloo Paratha'), findsNothing);
  });

  testWidgets('Campaign picker empty state when catalog has no PREORDER items', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddPreOrderProductScreen(
          campaignId: 'campaign-1',
          existingProductNames: const {},
          fetchListings: () async => [_listingJson('Samosa')],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No pre-order items yet'), findsOneWidget);
  });
}
