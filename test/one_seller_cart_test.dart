import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/food_detail_screen.dart';
import 'package:societybites/services/cart_controller.dart';
import 'package:societybites/services/session_service.dart';
import 'package:societybites/widgets/one_seller_cart.dart';

FoodItem _food({
  required String id,
  required String sellerId,
  required String sellerName,
  required String name,
}) {
  return FoodItem.fromJson({
    'id': id,
    'name': name,
    'sellerId': sellerId,
    'sellerName': sellerName,
    'price': 40,
    'quantity': 4,
    'status': 'active',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final puran = _food(
    id: 'p1',
    sellerId: 'puran',
    sellerName: "Puran's Kitchen",
    name: 'Kachori',
  );
  final aarav = _food(
    id: 'a1',
    sellerId: 'aarav',
    sellerName: "Aarav's Kitchen",
    name: 'Vada Pav',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CartController.instance.clear();
  });

  tearDown(CartController.instance.clear);

  test('empty cart and the same seller can be added', () {
    expect(canAddItemFromSeller(<CartItem>[], 'puran'), isTrue);
    expect(
      canAddItemFromSeller([CartItem(food: puran)], 'puran'),
      isTrue,
    );
    expect(
      canAddItemFromSeller([CartItem(food: puran)], 'aarav'),
      isFalse,
    );
  });

  testWidgets('empty cart Order Now opens checkout', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: FoodDetailScreen(food: aarav)),
    );
    await tester.tap(find.text('Order Now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('confirm-order')), findsOneWidget);
    expect(CartController.instance.items, isEmpty);
  });

  testWidgets('Order Now from another seller does not open checkout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CartController.instance.items.add(CartItem(food: puran));

    await tester.pumpWidget(
      MaterialApp(home: FoodDetailScreen(food: aarav)),
    );
    await tester.tap(find.text('Order Now'));
    await tester.pumpAndSettle();

    expect(find.text('Your cart already has items'), findsOneWidget);
    expect(find.textContaining("Puran's Kitchen"), findsWidgets);
    expect(find.textContaining("Aarav's Kitchen"), findsWidgets);
    expect(find.byKey(const Key('confirm-order')), findsNothing);
    expect(CartController.instance.items, hasLength(1));
    expect(CartController.instance.items.first.food.id, 'p1');
  });

  testWidgets('Continue Browsing leaves the current cart', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CartController.instance.items.add(CartItem(food: puran));

    await tester.pumpWidget(
      MaterialApp(home: FoodDetailScreen(food: aarav)),
    );
    await tester.tap(find.text('Order Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('one-seller-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Your cart already has items'), findsNothing);
    expect(find.text('Order Now'), findsOneWidget);
    expect(CartController.instance.items.single.food.sellerId, 'puran');
  });

  testWidgets('View Cart opens the existing cart unchanged', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await SessionService.saveToken('test-token');
    CartController.instance.items.add(CartItem(food: puran));

    await tester.pumpWidget(
      MaterialApp(home: FoodDetailScreen(food: aarav)),
    );
    await tester.tap(find.text('Order Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('one-seller-view-cart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('confirm-order')), findsOneWidget);
    expect(find.text('Kachori'), findsWidgets);
    expect(CartController.instance.items.single.food.id, 'p1');
    expect(CartController.instance.items.single.food.sellerId, 'puran');
  });
}
