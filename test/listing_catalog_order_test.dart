import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/utils/listing_catalog_order.dart';

FoodItem _item({
  required String id,
  int? displayOrder,
  DateTime? createdAt,
}) {
  return FoodItem(
    id: id,
    name: id,
    sellerId: 's1',
    sellerName: 'Seller',
    block: '',
    price: 10,
    rating: 4,
    pickupTime: '5 PM',
    description: '',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
    displayOrder: displayOrder,
    createdAt: createdAt,
  );
}

void main() {
  test('sortFoodItemsByCatalogOrder matches backend rules', () {
    final sorted = sortFoodItemsByCatalogOrder([
      _item(id: 'c', displayOrder: 2),
      _item(id: 'a', displayOrder: 0),
      _item(id: 'b', displayOrder: 1),
      _item(id: 'legacy', createdAt: DateTime(2024, 6, 1)),
    ]);
    expect(sorted.map((e) => e.id).toList(), ['a', 'b', 'c', 'legacy']);
  });

  test('a newly prepended listing at 0 stays above shifted catalog items', () {
    final sorted = sortFoodItemsByCatalogOrder([
      _item(id: 'old-a', displayOrder: 1),
      _item(id: 'old-b', displayOrder: 2),
      _item(id: 'new', displayOrder: 0),
    ]);
    expect(sorted.map((e) => e.id).toList(), ['new', 'old-a', 'old-b']);
  });
}
