import 'package:flutter/material.dart';

class Seller {
  final String id;
  final String name;
  final String block;
  final double rating;
  final int reviewCount;
  final IconData avatarIcon;
  final Color avatarColor;

  const Seller({
    required this.id,
    required this.name,
    required this.block,
    required this.rating,
    this.reviewCount = 0,
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
  final String? flatNumber;
  final String? pickupLocation;
  final double price;
  final double rating;
  final String pickupTime;
  final String description;
  final String? imageUrl;
  final String? imageCacheKey;
  final int quantity;
  final String? weightUnit;
  final String? weightValue;
  final List<String> tags;
  final String? category;
  final String status;
  final DateTime? availableAt;
  final int reviewCount;
  final IconData icon;
  final Color bgColor;
  final String? sellerUpiId;
  final String? campaignId;

  const FoodItem({
    required this.id,
    required this.name,
    required this.sellerId,
    required this.sellerName,
    required this.block,
    this.flatNumber,
    this.pickupLocation,
    required this.price,
    required this.rating,
    required this.pickupTime,
    required this.description,
    this.imageUrl,
    this.imageCacheKey,
    this.quantity = 1,
    this.weightUnit,
    this.weightValue,
    this.tags = const [],
    this.category,
    this.status = 'active',
    this.availableAt,
    this.reviewCount = 0,
    required this.icon,
    required this.bgColor,
    this.sellerUpiId,
    this.campaignId,
  });

  bool get isPreOrder {
    final id = campaignId?.trim();
    return id != null && id.isNotEmpty;
  }

  bool get isPaused => status == 'paused';
  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired';

  /// Human-readable pickup / seller location for cards and detail.
  String get locationLabel {
    final parts = <String>[];
    if (flatNumber != null && flatNumber!.isNotEmpty) {
      parts.add('Flat $flatNumber');
    }
    if (block.isNotEmpty && block != 'Block ?') {
      parts.add(block);
    }
    if (parts.isEmpty && pickupLocation != null && pickupLocation!.isNotEmpty) {
      return pickupLocation!;
    }
    if (parts.isEmpty) return 'Pickup at seller home';
    return parts.join(', ');
  }

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
    final availableAtRaw = json['availableAt'];
    final availableAt = availableAtRaw == null
        ? null
        : DateTime.tryParse(availableAtRaw.toString());

    return FoodItem(
      id: id,
      name: json['name'] as String,
      sellerId: json['sellerId'] as String,
      sellerName: (json['sellerName'] as String?) ?? 'Neighbor',
      block: (json['block'] as String?) ?? 'Block ?',
      flatNumber: json['flatNumber'] as String?,
      pickupLocation: json['pickupLocation'] as String?,
      price: (json['price'] as num).toDouble(),
      rating: (json['avgRating'] as num?)?.toDouble() ?? 0,
      pickupTime: _formatPickupTime(availableAtRaw),
      description: (json['description'] as String?) ?? '',
      imageUrl: json['imageUrl'] as String?,
      imageCacheKey: json['updatedAt'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      weightUnit: json['weightUnit'] as String?,
      weightValue: json['weightValue'] as String?,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      category: json['category'] as String?,
      status: (json['status'] as String?) ?? 'active',
      availableAt: availableAt,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      icon: _icons[hash % _icons.length],
      bgColor: _colors[hash % _colors.length],
      sellerUpiId: json['sellerUpiId'] as String?,
      campaignId: (json['campaignId'] as String?)?.trim().isEmpty == true
          ? null
          : json['campaignId'] as String?,
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
  final String? flatNumber;
  final String? block;
  final double rating;
  final String comment;
  final List<String> tags;
  final String? listingName;
  final DateTime? createdAt;

  const Review({
    required this.name,
    this.flatNumber,
    this.block,
    required this.rating,
    required this.comment,
    required this.tags,
    this.listingName,
    this.createdAt,
  });

  String get displayName {
    final parts = <String>[name];
    if (flatNumber != null && flatNumber!.isNotEmpty) {
      parts.add('Flat $flatNumber');
    }
    return parts.join(', ');
  }

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      name: (json['name'] as String?) ?? 'Neighbor',
      flatNumber: json['flatNumber'] as String?,
      block: json['block'] as String?,
      rating: (json['rating'] as num).toDouble(),
      comment: (json['comment'] as String?) ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      listingName: json['listingName'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
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
  final String status;
  final int statusStep;
  final double orderTotal;
  final double subtotal;
  final double communityFee;
  final double deliveryCharge;
  final String type;
  final String? campaignId;
  final String? fulfilmentMethod;
  final String? fulfilmentNotes;
  final DateTime? fulfilmentAt;
  final String? campaignTitle;
  final DateTime? campaignOrderCutoffAt;
  final String? paymentMethod;
  final String paymentStatus;
  final bool hasReview;
  final String? rejectReason;
  final DateTime? rejectedAt;
  final DateTime? expectedReadyAt;
  final String? buyerName;
  final String? buyerPhone;
  final String? buyerFlatNumber;
  final String? buyerBlock;
  final String? buyerSocietyName;

  const Order({
    required this.id,
    required this.orderId,
    required this.items,
    required this.date,
    required this.status,
    required this.statusStep,
    required this.orderTotal,
    required this.subtotal,
    required this.communityFee,
    this.deliveryCharge = 0,
    this.type = 'regular',
    this.campaignId,
    this.fulfilmentMethod,
    this.fulfilmentNotes,
    this.fulfilmentAt,
    this.campaignTitle,
    this.campaignOrderCutoffAt,
    this.paymentMethod,
    this.paymentStatus = 'pending',
    this.hasReview = false,
    this.rejectReason,
    this.rejectedAt,
    this.expectedReadyAt,
    this.buyerName,
    this.buyerPhone,
    this.buyerFlatNumber,
    this.buyerBlock,
    this.buyerSocietyName,
  });

  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';
  bool get isPreOrder => type == 'pre_order';
  bool get canCancelPreOrder =>
      isPreOrder &&
      campaignOrderCutoffAt != null &&
      DateTime.now().isBefore(campaignOrderCutoffAt!) &&
      (status == 'pending' || status == 'accepted');
  bool get isTerminal =>
      status == 'completed' || status == 'cancelled' || status == 'rejected';

  /// Show Ready-by estimate only before the order is actually marked ready.
  bool get showExpectedReadyAt =>
      expectedReadyAt != null &&
      (status == 'accepted' || status == 'preparing');

  /// Seller-facing buyer label: name + flat/block.
  String get buyerLabel {
    final parts = <String>[];
    final name = buyerName?.trim();
    if (name != null && name.isNotEmpty) parts.add(name);

    final location = <String>[];
    if (buyerBlock != null && buyerBlock!.trim().isNotEmpty) {
      location.add('Block ${buyerBlock!.trim()}');
    }
    if (buyerFlatNumber != null && buyerFlatNumber!.trim().isNotEmpty) {
      location.add('Flat ${buyerFlatNumber!.trim()}');
    }
    if (location.isNotEmpty) parts.add(location.join(', '));

    if (parts.isEmpty) return 'Neighbor';
    return parts.join(' · ');
  }

  FoodItem get food => items.isNotEmpty ? items.first.food : _placeholderFood;

  int get quantity => items.fold<int>(0, (sum, item) => sum + item.quantity);

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

  Order withCampaign(PreOrderCampaign campaign) {
    return Order(
      id: id,
      orderId: orderId,
      items: items,
      date: date,
      status: status,
      statusStep: statusStep,
      orderTotal: orderTotal,
      subtotal: subtotal,
      communityFee: communityFee,
      deliveryCharge: deliveryCharge,
      type: type,
      campaignId: campaignId,
      fulfilmentMethod: fulfilmentMethod,
      fulfilmentNotes: fulfilmentNotes,
      fulfilmentAt: fulfilmentAt,
      campaignTitle: campaign.title,
      campaignOrderCutoffAt: campaign.orderCutoffAt,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      hasReview: hasReview,
      rejectReason: rejectReason,
      rejectedAt: rejectedAt,
      expectedReadyAt: expectedReadyAt,
      buyerName: buyerName,
      buyerPhone: buyerPhone,
      buyerFlatNumber: buyerFlatNumber,
      buyerBlock: buyerBlock,
      buyerSocietyName: buyerSocietyName,
    );
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
        .map(
          (item) =>
              OrderLineItem.fromJson(Map<String, dynamic>.from(item as Map)),
        )
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
      status: (json['status'] as String?) ?? 'pending',
      statusStep: (json['statusStep'] as num?)?.toInt() ?? 0,
      orderTotal: apiTotal ?? computedSubtotal,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? computedSubtotal,
      communityFee: (json['communityFee'] as num?)?.toDouble() ?? 0,
      deliveryCharge: (json['deliveryCharge'] as num?)?.toDouble() ?? 0,
      type: (json['type'] as String?) ?? 'regular',
      campaignId: json['campaignId'] as String?,
      fulfilmentMethod: json['fulfilmentMethod'] as String?,
      fulfilmentNotes: json['fulfilmentNotes'] as String?,
      fulfilmentAt: DateTime.tryParse(json['fulfilmentAt']?.toString() ?? ''),
      paymentMethod: json['paymentMethod'] as String?,
      paymentStatus: (json['paymentStatus'] as String?) ?? 'pending',
      hasReview: json['hasReview'] == true,
      rejectReason: json['rejectReason'] as String?,
      rejectedAt: DateTime.tryParse(json['rejectedAt']?.toString() ?? ''),
      expectedReadyAt: DateTime.tryParse(
        json['expectedReadyAt']?.toString() ?? '',
      ),
      buyerName: json['buyerName'] as String?,
      buyerPhone: json['buyerPhone'] as String?,
      buyerFlatNumber: json['buyerFlatNumber'] as String?,
      buyerBlock: json['buyerBlock'] as String?,
      buyerSocietyName: json['buyerSocietyName'] as String?,
    );
  }

  static String formatReadyBy(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final time =
        '${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $ampm';
    if (sameDay) return time;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${local.day} ${months[local.month - 1]}, $time';
  }

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

class PreOrderProduct {
  final String listingId;
  final String name;
  final String sellerId;
  final String sellerName;
  final String block;
  final String? flatNumber;
  final double rating;
  final int reviewCount;
  final double price;
  final String inventoryMode;
  final int quantity;
  final String? description;
  final String? imageUrl;

  const PreOrderProduct({
    required this.listingId,
    required this.name,
    required this.sellerId,
    required this.sellerName,
    this.block = '',
    this.flatNumber,
    this.rating = 0,
    this.reviewCount = 0,
    required this.price,
    required this.inventoryMode,
    required this.quantity,
    this.description,
    this.imageUrl,
  });

  factory PreOrderProduct.fromJson(Map<String, dynamic> json) {
    return PreOrderProduct(
      listingId: (json['id'] ?? json['listingId']).toString(),
      name: (json['name'] ?? json['productName'] ?? 'Product').toString(),
      sellerId: (json['sellerId'] as String?) ?? '',
      sellerName: (json['sellerName'] as String?) ?? 'Neighbor',
      block: (json['block'] as String?) ?? '',
      flatNumber: json['flatNumber'] as String?,
      rating: (json['avgRating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      inventoryMode: (json['inventoryMode'] as String?) ?? 'demand',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class PreOrderCampaign {
  final String id;
  final String sellerId;
  final String title;
  final String? description;
  final String? coverImageUrl;
  final String? fulfilmentNotes;
  final String status;
  final DateTime orderOpenAt;
  final DateTime orderCutoffAt;
  final DateTime fulfilmentAt;
  final List<String> offeredFulfilmentMethods;
  final double defaultDeliveryCharge;
  final List<PreOrderProduct> products;
  final int totalOrders;
  final int totalItems;
  final double foodSubtotal;

  const PreOrderCampaign({
    required this.id,
    this.sellerId = '',
    required this.title,
    this.description,
    this.coverImageUrl,
    this.fulfilmentNotes,
    required this.status,
    required this.orderOpenAt,
    required this.orderCutoffAt,
    required this.fulfilmentAt,
    this.offeredFulfilmentMethods = const ['pickup'],
    this.defaultDeliveryCharge = 0,
    this.products = const [],
    this.totalOrders = 0,
    this.totalItems = 0,
    this.foodSubtotal = 0,
  });

  bool get isOpen =>
      status == 'open' && DateTime.now().isBefore(orderCutoffAt.toLocal());

  String get sellerName =>
      products.isNotEmpty ? products.first.sellerName : 'Neighbor';

  double get startingPrice => products.isEmpty
      ? 0
      : products
            .map((product) => product.price)
            .reduce((a, b) => a < b ? a : b);

  factory PreOrderCampaign.fromJson(Map<String, dynamic> json) {
    final rawProducts = json['products'] as List? ?? const [];
    return PreOrderCampaign(
      id: (json['id'] ?? json['campaignId']).toString(),
      sellerId: (json['sellerId'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Pre-order campaign',
      description: json['description'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      fulfilmentNotes: json['fulfilmentNotes'] as String?,
      status: (json['status'] as String?) ?? 'draft',
      orderOpenAt: DateTime.parse(json['orderOpenAt'].toString()).toLocal(),
      orderCutoffAt: DateTime.parse(json['orderCutoffAt'].toString()).toLocal(),
      fulfilmentAt: DateTime.parse(json['fulfilmentAt'].toString()).toLocal(),
      offeredFulfilmentMethods:
          (json['offeredFulfilmentMethods'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['pickup'],
      defaultDeliveryCharge:
          (json['defaultDeliveryCharge'] as num?)?.toDouble() ?? 0,
      products: rawProducts
          .map(
            (e) =>
                PreOrderProduct.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      totalOrders: (json['totalOrders'] as num?)?.toInt() ?? 0,
      totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
      foodSubtotal: (json['foodSubtotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PreOrderProductionItem {
  final String listingId;
  final String productName;
  final int quantityToPrepare;

  const PreOrderProductionItem({
    required this.listingId,
    required this.productName,
    required this.quantityToPrepare,
  });

  factory PreOrderProductionItem.fromJson(Map<String, dynamic> json) {
    return PreOrderProductionItem(
      listingId: json['listingId'].toString(),
      productName: (json['productName'] as String?) ?? 'Product',
      quantityToPrepare: (json['quantityToPrepare'] as num?)?.toInt() ?? 0,
    );
  }
}

class PreOrderSummary {
  final String campaignId;
  final String title;
  final String? coverImageUrl;
  final String status;
  final DateTime orderOpenAt;
  final DateTime orderCutoffAt;
  final DateTime fulfilmentAt;
  final int totalOrders;
  final int totalItems;
  final double foodSubtotal;
  final int pickupOrders;
  final int sellerDeliveryOrders;
  final List<PreOrderProductionItem> products;

  const PreOrderSummary({
    required this.campaignId,
    required this.title,
    this.coverImageUrl,
    required this.status,
    required this.orderOpenAt,
    required this.orderCutoffAt,
    required this.fulfilmentAt,
    required this.totalOrders,
    required this.totalItems,
    required this.foodSubtotal,
    required this.pickupOrders,
    required this.sellerDeliveryOrders,
    required this.products,
  });

  factory PreOrderSummary.fromJson(Map<String, dynamic> json) {
    final fulfilment = Map<String, dynamic>.from(
      json['fulfilment'] as Map? ?? const {},
    );
    return PreOrderSummary(
      campaignId: json['campaignId'].toString(),
      title: (json['title'] as String?) ?? 'Pre-order campaign',
      coverImageUrl: json['coverImageUrl'] as String?,
      status: (json['status'] as String?) ?? 'draft',
      orderOpenAt: DateTime.parse(json['orderOpenAt'].toString()).toLocal(),
      orderCutoffAt: DateTime.parse(json['orderCutoffAt'].toString()).toLocal(),
      fulfilmentAt: DateTime.parse(json['fulfilmentAt'].toString()).toLocal(),
      totalOrders: (json['totalOrders'] as num?)?.toInt() ?? 0,
      totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
      foodSubtotal: (json['foodSubtotal'] as num?)?.toDouble() ?? 0,
      pickupOrders: (fulfilment['pickup'] as num?)?.toInt() ?? 0,
      sellerDeliveryOrders:
          (fulfilment['seller_delivery'] as num?)?.toInt() ?? 0,
      products: (json['products'] as List? ?? const [])
          .map(
            (e) => PreOrderProductionItem.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }
}

Seller sellerFromListing(FoodItem food, {double? rating, int? reviewCount}) {
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
    rating: rating ?? food.rating,
    reviewCount: reviewCount ?? food.reviewCount,
    avatarIcon: avatarIcons[hash % avatarIcons.length],
    avatarColor: avatarColors[hash % avatarColors.length],
  );
}

List<Seller> sellersFromListings(List<FoodItem> listings) {
  final grouped = <String, List<FoodItem>>{};
  for (final food in listings) {
    grouped.putIfAbsent(food.sellerId, () => []).add(food);
  }
  final sellers = grouped.values.map((sellerListings) {
    final first = sellerListings.first;
    final reviews = sellerListings.fold<int>(
      0,
      (sum, item) => sum + item.reviewCount,
    );
    final weightedRating = reviews == 0
        ? 0.0
        : sellerListings.fold<double>(
                0,
                (sum, item) => sum + item.rating * item.reviewCount,
              ) /
              reviews;
    return sellerFromListing(
      first,
      rating: weightedRating,
      reviewCount: reviews,
    );
  }).toList();
  sellers.sort((a, b) => b.rating.compareTo(a.rating));
  return sellers;
}

Seller sellerFromPreOrderCampaign(PreOrderCampaign campaign) {
  final firstProduct = campaign.products.isEmpty
      ? null
      : campaign.products.first;
  final hash = campaign.sellerId.hashCode.abs();
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
  final reviewCount = campaign.products.fold<int>(
    0,
    (sum, product) => sum + product.reviewCount,
  );
  final rating = reviewCount == 0
      ? 0.0
      : campaign.products.fold<double>(
              0,
              (sum, product) => sum + product.rating * product.reviewCount,
            ) /
            reviewCount;
  return Seller(
    id: campaign.sellerId,
    name: campaign.sellerName,
    block: firstProduct?.block ?? '',
    rating: rating,
    reviewCount: reviewCount,
    avatarIcon: avatarIcons[hash % avatarIcons.length],
    avatarColor: avatarColors[hash % avatarColors.length],
  );
}
