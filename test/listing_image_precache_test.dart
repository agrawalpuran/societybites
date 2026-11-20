import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/utils/listing_image_precache.dart';

FoodItem _food(String id, {String? imageUrl}) {
  return FoodItem(
    id: id,
    name: id,
    sellerId: 's-$id',
    sellerName: 'Seller',
    block: 'A',
    price: 100,
    rating: 0,
    pickupTime: 'Ready',
    description: '',
    imageUrl: imageUrl ?? 'https://example.com/$id.jpg',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
  );
}

void main() {
  test('first-screen photos are warmed and the rest of the feed is not', () {
    final visible = [_food('a'), _food('b')];
    final warmed = homeListingImagesToWarm(
      [_food('c'), _food('d'), ...visible],
      priority: visible,
    );

    expect(warmed.map((food) => food.id), ['a', 'b']);
  });

  test('a dish without a photo does not take a warmup slot', () {
    final warmed = homeListingImagesToWarm(
      const [],
      priority: [_food('blank', imageUrl: ''), _food('shown')],
      maxCount: 1,
    );

    expect(warmed.map((food) => food.id), ['shown']);
  });

  test('with no first screen, warmup stays on the ranked cap', () {
    final warmed = homeListingImagesToWarm(
      [for (var i = 0; i < 10; i++) _food('$i')],
      maxCount: 3,
    );

    expect(warmed.map((food) => food.id), ['0', '1', '2']);
  });
}
