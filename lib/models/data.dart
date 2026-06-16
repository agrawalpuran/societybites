import 'package:flutter/material.dart';

class Seller {
  final String id;
  final String name;
  final String block;
  final double rating;
  final IconData avatarIcon;
  final Color avatarColor;

  const Seller({
    required this.id,
    required this.name,
    required this.block,
    required this.rating,
    required this.avatarIcon,
    required this.avatarColor,
  });
}

class FoodItem {
  final String id;
  final String name;
  final String sellerId;
  final String sellerName;
  final String block;
  final double price;
  final double rating;
  final String pickupTime;
  final String description;
  final String? imageUrl;
  final String? imageCacheKey;
  final IconData icon;
  final Color bgColor;

  const FoodItem({
    required this.id,
    required this.name,
    required this.sellerId,
    required this.sellerName,
    required this.block,
    required this.price,
    required this.rating,
    required this.pickupTime,
    required this.description,
    this.imageUrl,
    this.imageCacheKey,
    required this.icon,
    required this.bgColor,
  });

  static const _icons = [
    Icons.rice_bowl,
    Icons.dinner_dining,
    Icons.cake,
    Icons.lunch_dining,
    Icons.breakfast_dining,
    Icons.bakery_dining,
    Icons.restaurant,
    Icons.local_pizza,
  ];

  static const _colors = [
    Color(0xFFF5F0E8),
    Color(0xFF2A2A2A),
    Color(0xFFFFF0F0),
    Color(0xFFF5EEE0),
    Color(0xFFF0EDE5),
    Color(0xFFFFF5EE),
    Color(0xFFEEF5EE),
    Color(0xFFE8F5EE),
  ];

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final hash = id.hashCode.abs();
    final availableAt = json['availableAt'];

    return FoodItem(
      id: id,
      name: json['name'] as String,
      sellerId: json['sellerId'] as String,
      sellerName: (json['sellerName'] as String?) ?? 'Neighbor',
      block: (json['block'] as String?) ?? 'Block ?',
      price: (json['price'] as num).toDouble(),
      rating: 4.8,
      pickupTime: _formatPickupTime(availableAt),
      description: (json['description'] as String?) ?? '',
      imageUrl: json['imageUrl'] as String?,
      imageCacheKey: json['updatedAt'] as String?,
      icon: _icons[hash % _icons.length],
      bgColor: _colors[hash % _colors.length],
    );
  }

  static String _formatPickupTime(dynamic availableAt) {
    if (availableAt == null) return '15 min';
    final dt = DateTime.tryParse(availableAt.toString());
    if (dt == null) return '15 min';
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${hour == 0 ? 12 : hour}:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }
}

class CartItem {
  final FoodItem food;
  int quantity;

  CartItem({required this.food, this.quantity = 1});

  double get total => food.price * quantity;
}

class Review {
  final String name;
  final double rating;
  final String comment;
  final List<String> tags;

  const Review({
    required this.name,
    required this.rating,
    required this.comment,
    required this.tags,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      name: (json['name'] as String?) ?? 'Neighbor',
      rating: (json['rating'] as num).toDouble(),
      comment: (json['comment'] as String?) ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class OrderLineItem {
  final FoodItem food;
  final int quantity;
  final double unitPrice;

  const OrderLineItem({
    required this.food,
    required this.quantity,
    required this.unitPrice,
  });

  double get lineTotal => unitPrice * quantity;

  factory OrderLineItem.fromJson(Map<String, dynamic> json) {
    final listingJson = json['listing'] as Map?;
    final food = listingJson != null
        ? FoodItem.fromJson(Map<String, dynamic>.from(listingJson))
        : FoodItem.fromJson({
            'id': 'unknown',
            'name': 'Order item',
            'sellerId': '',
            'price': json['unitPrice'] ?? 0,
          });

    return OrderLineItem(
      food: food,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? food.price,
    );
  }
}

class Order {
  final String id;
  final String orderId;
  final List<OrderLineItem> items;
  final String date;
  final int statusStep;
  final double orderTotal;
  final double subtotal;
  final double communityFee;
  final String? paymentMethod;

  const Order({
    required this.id,
    required this.orderId,
    required this.items,
    required this.date,
    required this.statusStep,
    required this.orderTotal,
    required this.subtotal,
    required this.communityFee,
    this.paymentMethod,
  });

  FoodItem get food =>
      items.isNotEmpty ? items.first.food : _placeholderFood;

  int get quantity =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  double get total => orderTotal;

  String get itemsSummary {
    if (items.isEmpty) return 'Order item';
    if (items.length == 1) {
      return items.first.quantity > 1
          ? '${items.first.food.name} ×${items.first.quantity}'
          : items.first.food.name;
    }
    return '${items.length} items ($quantity portions)';
  }

  String get sellerLabel {
    if (items.isEmpty) return 'Neighbor';
    final sellers = items.map((item) => item.food.sellerName).toSet().toList();
    return sellers.join(', ');
  }

  static const _placeholderFood = FoodItem(
    id: 'unknown',
    name: 'Order item',
    sellerId: '',
    sellerName: 'Neighbor',
    block: '',
    price: 0,
    rating: 0,
    pickupTime: '',
    description: '',
    icon: Icons.restaurant,
    bgColor: Color(0xFFF0F2F1),
  );

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? [];
    final items = rawItems
        .map((item) => OrderLineItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ))
        .toList();

    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final date = createdAt != null ? _formatDate(createdAt) : 'Today';

    final apiTotal = (json['total'] as num?)?.toDouble();
    final computedSubtotal = items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );

    return Order(
      id: json['id'] as String,
      orderId: (json['orderId'] as String?) ?? (json['orderNumber'] as String),
      items: items,
      date: date,
      statusStep: (json['statusStep'] as num?)?.toInt() ?? 0,
      orderTotal: apiTotal ?? computedSubtotal,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? computedSubtotal,
      communityFee: (json['communityFee'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['paymentMethod'] as String?,
    );
  }

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

Seller sellerFromListing(FoodItem food, {double rating = 4.8}) {
  final hash = food.sellerId.hashCode.abs();
  const avatarIcons = [
    Icons.person,
    Icons.restaurant,
    Icons.cake,
    Icons.lunch_dining,
    Icons.bakery_dining,
  ];
  const avatarColors = [
    Color(0xFFE8D5C4),
    Color(0xFFD5E8D4),
    Color(0xFFD4D5E8),
    Color(0xFFE8E4D4),
    Color(0xFFE8D4D8),
  ];

  return Seller(
    id: food.sellerId,
    name: food.sellerName,
    block: food.block,
    rating: rating,
    avatarIcon: avatarIcons[hash % avatarIcons.length],
    avatarColor: avatarColors[hash % avatarColors.length],
  );
}

List<Seller> sellersFromListings(List<FoodItem> listings) {
  final seen = <String>{};
  final sellers = <Seller>[];

  for (final food in listings) {
    if (seen.add(food.sellerId)) {
      sellers.add(sellerFromListing(food));
    }
  }

  return sellers;
}
