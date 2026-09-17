import 'package:flutter/material.dart';

class GuestHeroSlide {
  const GuestHeroSlide({
    required this.assetPath,
    required this.liveTag,
    required this.locationTag,
    required this.portionsTag,
    required this.kitchenLabel,
    required this.title,
    required this.priceLabel,
    required this.ratingLabel,
    this.pickupTag,
    required this.category,
  });

  final String assetPath;
  final String liveTag;
  final String locationTag;
  final String portionsTag;
  final String kitchenLabel;
  final String title;
  final String priceLabel;
  final String ratingLabel;
  final String? pickupTag;
  final String category;
}

class GuestCuratedCategory {
  const GuestCuratedCategory({
    required this.title,
    required this.homeCategory,
    required this.icon,
    required this.accent,
  });

  final String title;

  /// Matches Home listing categories.
  final String homeCategory;
  final IconData icon;
  final Color accent;
}

/// Presentation-only discovery content for logged-out browsing.
/// Not written to SessionService or the backend.
class GuestDiscovery {
  GuestDiscovery._();

  static const heroSlides = [
    GuestHeroSlide(
      assetPath: 'assets/images/guest/hero_food_1.jpg',
      liveTag: 'LIVE TODAY',
      locationTag: 'TOWER B · #402',
      portionsTag: '12 portions left',
      kitchenLabel: "ELENA'S KITCHEN SHOWCASE",
      title: 'Fresh Pappardelle & Artisanal Sourdough',
      priceLabel: '\$12.50',
      ratingLabel: '★ 4.9 (42)',
      pickupTag: 'Pickup 12:30 - 1:15 PM',
      category: 'Lunch',
    ),
    GuestHeroSlide(
      assetPath: 'assets/images/guest/hero_food_2.jpg',
      liveTag: 'LIVE TODAY',
      locationTag: 'BLOCK A · #12',
      portionsTag: '8 portions left',
      kitchenLabel: "ANITA'S KITCHEN SHOWCASE",
      title: 'Homemade Hyderabadi Chicken Biryani',
      priceLabel: '₹220',
      ratingLabel: '★ 4.8 (31)',
      pickupTag: 'Pickup 7:00 - 8:00 PM',
      category: 'Lunch',
    ),
    GuestHeroSlide(
      assetPath: 'assets/images/guest/hero_food_3.jpg',
      liveTag: 'BAKED THIS MORNING',
      locationTag: 'TOWER C · #108',
      portionsTag: '6 loaves left',
      kitchenLabel: "PRIYA'S BAKERY SHOWCASE",
      title: 'Butter Croissants & Honey Cake',
      priceLabel: '₹180',
      ratingLabel: '★ 4.9 (28)',
      pickupTag: 'Pickup 8:00 - 9:30 AM',
      category: 'Homemade Specials',
    ),
    GuestHeroSlide(
      assetPath: 'assets/images/guest/hero_food_4.jpg',
      liveTag: 'HEALTHY PICK',
      locationTag: 'BLOCK D · #21',
      portionsTag: '10 portions left',
      kitchenLabel: "MEERA'S KITCHEN SHOWCASE",
      title: 'Millet Bowl & Citrus Salad',
      priceLabel: '₹160',
      ratingLabel: '★ 4.7 (19)',
      pickupTag: 'Pickup 12:00 - 1:00 PM',
      category: 'Healthy',
    ),
  ];

  static const curatedCategories = [
    GuestCuratedCategory(
      title: 'Warm Meals',
      homeCategory: 'Lunch',
      icon: Icons.ramen_dining_rounded,
      accent: Color(0xFF0E5A47),
    ),
    GuestCuratedCategory(
      title: 'Artisan Bakes',
      homeCategory: 'Homemade Specials',
      icon: Icons.bakery_dining_rounded,
      accent: Color(0xFFC46A2B),
    ),
    GuestCuratedCategory(
      title: 'Healthy Eats',
      homeCategory: 'Healthy',
      icon: Icons.eco_rounded,
      accent: Color(0xFF2F7A6B),
    ),
    GuestCuratedCategory(
      title: 'Desserts',
      homeCategory: 'Desserts',
      icon: Icons.cake_rounded,
      accent: Color(0xFFB35A6A),
    ),
  ];

  static List<Map<String, dynamic>> listingMaps() {
    return [
      _listing(
        id: 'guest-pappardelle',
        name: 'Fresh Pappardelle & Artisanal Sourdough',
        sellerId: 'guest-kitchen-elena',
        sellerName: 'Elena',
        block: 'Tower B',
        flatNumber: '402',
        price: 850,
        rating: 4.9,
        reviews: 42,
        quantity: 12,
        category: 'Lunch',
        image: 'asset:assets/images/guest/hero_food_1.jpg',
        description:
            'Slow-simmered sauce and a warm loaf, made by a verified resident cook.',
      ),
      _listing(
        id: 'guest-biryani',
        name: 'Homemade Hyderabadi Chicken Biryani',
        sellerId: 'guest-kitchen-anita',
        sellerName: 'Anita',
        block: 'Block A',
        flatNumber: '12',
        price: 220,
        rating: 4.8,
        reviews: 31,
        quantity: 8,
        category: 'Lunch',
        image: 'asset:assets/images/guest/hero_food_2.jpg',
        description: 'Fragrant home-style biryani finished with fried onions.',
      ),
      _listing(
        id: 'guest-bakes',
        name: 'Butter Croissants & Honey Cake',
        sellerId: 'guest-kitchen-priya',
        sellerName: 'Priya',
        block: 'Tower C',
        flatNumber: '108',
        price: 180,
        rating: 4.9,
        reviews: 28,
        quantity: 6,
        category: 'Homemade Specials',
        image: 'asset:assets/images/guest/hero_food_3.jpg',
        description: 'Morning bakes from a neighbor kitchen, best enjoyed warm.',
      ),
      _listing(
        id: 'guest-millet',
        name: 'Millet Bowl & Citrus Salad',
        sellerId: 'guest-kitchen-meera',
        sellerName: 'Meera',
        block: 'Block D',
        flatNumber: '21',
        price: 160,
        rating: 4.7,
        reviews: 19,
        quantity: 10,
        category: 'Healthy',
        image: 'asset:assets/images/guest/hero_food_4.jpg',
        description: 'Light, fresh portions made for weekday lunches.',
      ),
      _listing(
        id: 'guest-kheer',
        name: 'Cardamom Rice Kheer',
        sellerId: 'guest-kitchen-priya',
        sellerName: 'Priya',
        block: 'Tower C',
        flatNumber: '108',
        price: 90,
        rating: 4.8,
        reviews: 16,
        quantity: 9,
        category: 'Desserts',
        image: 'asset:assets/images/guest/hero_food_3.jpg',
        description: 'A small-batch dessert finished with toasted nuts.',
      ),
    ];
  }

  static Future<List<Map<String, dynamic>>> fetchListings() async {
    return listingMaps();
  }

  static Future<List<Map<String, dynamic>>> fetchListingsForSeller(
    String sellerId,
  ) async {
    return listingMaps()
        .where((item) => item['sellerId'] == sellerId)
        .toList();
  }

  static Map<String, dynamic> _listing({
    required String id,
    required String name,
    required String sellerId,
    required String sellerName,
    required String block,
    required String flatNumber,
    required double price,
    required double rating,
    required int reviews,
    required int quantity,
    required String category,
    required String image,
    required String description,
  }) {
    return {
      'id': id,
      'name': name,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'block': block,
      'flatNumber': flatNumber,
      'price': price,
      'avgRating': rating,
      'reviewCount': reviews,
      'quantity': quantity,
      'status': 'active',
      'category': category,
      'imageUrl': image,
      'description': description,
      'pickupLocation': 'My Home (Verified)',
    };
  }
}
