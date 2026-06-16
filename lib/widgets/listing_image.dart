import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';

class ListingImage extends StatelessWidget {
  const ListingImage({
    super.key,
    required this.food,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.iconSize = 36,
  });

  final FoodItem food;
  final double? width;
  final double? height;
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final imageUrl = food.imageUrl;
    final resolvedUrl = imageUrl != null && imageUrl.isNotEmpty
        ? ApiService.imageUrl(imageUrl, cacheKey: food.imageCacheKey)
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width,
        height: height,
        color: food.bgColor,
        child: resolvedUrl != null
            ? Image.network(
                resolvedUrl,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _iconFallback(),
              )
            : _iconFallback(),
      ),
    );
  }

  Widget _iconFallback() {
    return Center(
      child: Icon(
        food.icon,
        size: iconSize,
        color: const Color(0xFF6A7774),
      ),
    );
  }
}
