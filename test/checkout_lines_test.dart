import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/widgets/one_seller_cart.dart';

FoodItem _food({required String id, required String sellerId}) {
  return FoodItem(
    id: id,
    name: 'Snack',
    sellerId: sellerId,
    sellerName: 'Chef',
    block: 'A',
    price: 50,
    rating: 4,
    pickupTime: '10m',
    description: '',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFF0F2F1),
  );
}

void main() {
  test('checkoutLinesForFood keeps same-seller cart items', () {
    final a = _food(id: 'a', sellerId: 's1');
    final b = _food(id: 'b', sellerId: 's1');
    final lines = checkoutLinesForFood(
      food: b,
      globalCart: [CartItem(food: a, quantity: 2)],
    );
    expect(lines.length, 2);
    expect(lines.first.quantity, 2);
    expect(lines.last.food.id, 'b');
  });

  test('checkoutLinesForFood uses single item for different seller', () {
    final a = _food(id: 'a', sellerId: 's1');
    final b = _food(id: 'b', sellerId: 's2');
    final lines = checkoutLinesForFood(
      food: b,
      globalCart: [CartItem(food: a)],
    );
    expect(lines.length, 1);
    expect(lines.single.food.id, 'b');
  });
}
