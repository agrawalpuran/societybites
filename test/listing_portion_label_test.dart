import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/utils/listing_portion_label.dart';

void main() {
  test('grams portion label', () {
    expect(
      listingPortionLabel(weightValue: '250', weightUnit: 'grams'),
      '250 g',
    );
  });

  test('price per unit includes portion', () {
    final food = FoodItem(
      id: '1',
      name: 'Pickle',
      sellerId: 's',
      sellerName: 'A',
      block: 'B',
      price: 250,
      rating: 0,
      pickupTime: '6 PM',
      description: '',
      icon: Icons.restaurant,
      bgColor: const Color(0xFFE8F5EE),
      weightValue: '250',
      weightUnit: 'grams',
    );
    expect(listingPricePerUnitLabel(food), '₹250 / 250 g');
  });
}
