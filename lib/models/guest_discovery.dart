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
      priceLabel: '\₹175',
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

}
