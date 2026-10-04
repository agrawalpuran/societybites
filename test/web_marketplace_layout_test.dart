import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/web/web_breakpoints.dart';
import 'package:societybites/web/web_marketplace_home.dart';
import 'package:societybites/web/web_marketplace_states.dart';
import 'package:societybites/web/web_seller_card.dart';
import 'package:societybites/web/web_shell_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'society_name': 'Palm Grove',
      'user_name': 'Asha',
    });
  });

  test('web layout stays off unless the browser is wide enough', () {
    expect(webMarketplaceLayoutEnabled(isWeb: false, width: 1440), isFalse);
    expect(webMarketplaceLayoutEnabled(isWeb: true, width: 767), isFalse);
    expect(webMarketplaceLayoutEnabled(isWeb: true, width: 768), isTrue);
    expect(webFoodColumnCount(1400), 4);
    expect(webFoodColumnCount(1000), 3);
    expect(webFoodColumnCount(800), 2);
    expect(webSellerColumnCount(1400), 4);
    expect(webSellerColumnCount(800), 2);
  });

  testWidgets('startup frame does not show a plain loading line', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WebStartupFrame()));
    expect(find.text('SocietyEats'), findsOneWidget);
    expect(find.textContaining('Loading'), findsNothing);
  });

  testWidgets('desktop marketplace lays out real listing data', (tester) async {
    await _setWindow(tester, 1440, 1200);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: _sampleHome()));
    await tester.pump();

    expect(find.byKey(const Key('web-marketplace-home')), findsOneWidget);
    expect(
      find.text('Fresh flavors from\nyour Society and\nneighbourhood.'),
      findsOneWidget,
    );
    expect(find.textContaining('Prestige'), findsNothing);
    expect(find.text('Lemon rice'), findsWidgets);
    expect(find.text('Mina'), findsWidgets);
    expect(find.text('Add'), findsWidgets);
    expect(find.text('IN YOUR SOCIETY'), findsWidgets);
    expect(find.text('COOKS NEARBY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet width keeps the web marketplace without overflow', (
    tester,
  ) async {
    await _setWindow(tester, 900, 1400);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: _sampleHome()));
    await tester.pump();

    expect(find.text('Lemon rice'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('web header stays on one line at desktop and tablet widths', (
    tester,
  ) async {
    for (final width in [1440.0, 820.0]) {
      await _setWindow(tester, width, 900);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebShellHeader(
              selectedTab: 0,
              selectedFoodType: null,
              onSelectTab: (_) {},
              onFoodTypeChanged: (_) {},
              onSearchChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('web-shell-header')), findsOneWidget);
      expect(find.text('Home'), width >= 1080 ? findsOneWidget : findsNothing);
      expect(
        find.text('Explore'),
        width >= 1080 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('kitchen card blurs a cook who is not selling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebSellerCard(
            seller: const Seller(
              id: 'sirisha',
              name: 'Sirisha',
              block: 'Block C',
              rating: 4.2,
              reviewCount: 3,
              avatarIcon: Icons.person,
              avatarColor: Color(0xFFE7F2EA),
              hasOrderableItems: false,
            ),
            detail: 'Breakfast · Block C · 9 listings',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Sirisha'), findsOneWidget);
    expect(find.text(sellerNotAvailableLabel), findsOneWidget);
    expect(find.text('View menu'), findsNothing);
    expect(find.textContaining('9 listings'), findsNothing);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });
}

Future<void> _setWindow(
  WidgetTester tester,
  double width,
  double height,
) async {
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(Size(width, height));
}

WebMarketplaceHome _sampleHome() {
  final food = FoodItem(
    id: 'l1',
    name: 'Lemon rice',
    sellerId: 's1',
    sellerName: 'Mina',
    block: 'A',
    price: 120,
    rating: 4.8,
    pickupTime: '1:00 PM',
    description: 'Home cooked',
    quantity: 4,
    foodType: 'VEG',
    category: 'Lunch',
    icon: Icons.rice_bowl,
    bgColor: const Color(0xFFF5F0E8),
    reviewCount: 6,
  );
  final seller = Seller(
    id: 's1',
    name: 'Mina',
    block: 'A',
    rating: 4.8,
    reviewCount: 6,
    avatarIcon: Icons.person,
    avatarColor: const Color(0xFFE7F2EA),
  );
  return WebMarketplaceHome(
    isInitialLoading: false,
    isSlow: false,
    errorMessage: null,
    showEmptySociety: false,
    searching: false,
    searchQuery: '',
    selectedCategory: null,
    categories: const ['All', 'Lunch'],
    categoryCounts: const {'All': 1, 'Lunch': 1},
    heroFoods: [food],
    allFiltered: [food],
    highlights: [food],
    highlightSellers: [seller],
    sellerListings: [food],
    readyNow: [food],
    madeToOrder: const [],
    nearbyListings: const [],
    nearbySellers: const [],
    nearbySubtitle: null,
    extendedListings: const [],
    extendedSellers: const [],
    extendedSubtitle: null,
    otherListings: const [],
    inSocietyPreorders: const [],
    nearbyPreorders: const [],
    extendedPreorders: const [],
    preordersLoading: false,
    viewerUserId: null,
    expandedReach: null,
    cartQtyFor: (_) => 0,
    onAdd: (_) {},
    onRemove: (_) {},
    onOpenFood: (_) {},
    onOpenSeller: (_) {},
    onOpenCampaign: (_) {},
    onSeePreorders: () {},
    onCategorySelected: (_) {},
    onExpandReach: (_) {},
    onCollapseReach: (_) {},
    onRetry: () {},
    onRefresh: () async {},
    onStartSelling: () {},
    onExploreNearby: () {},
    onSelectTab: (_) {},
  );
}
