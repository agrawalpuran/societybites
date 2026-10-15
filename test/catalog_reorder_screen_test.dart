import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/screens/catalog_reorder_screen.dart';

FoodItem _food(String id) => FoodItem(
      id: id,
      name: 'Item $id',
      sellerId: 's1',
      sellerName: 'Seller',
      block: '',
      price: 10,
      rating: 4,
      pickupTime: '5 PM',
      description: '',
      icon: Icons.restaurant,
      bgColor: const Color(0xFFE8F5EE),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'user_id': 'seller-1'});
  });

  testWidgets('save order calls API seam and pops with true', (tester) async {
    var savedIds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogReorderScreen(
          initialItems: [_food('a'), _food('b')],
          saveOrder: (ids) async {
            savedIds = ids;
            return ids;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Order'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(savedIds, ['b', 'a']);
  });
}
