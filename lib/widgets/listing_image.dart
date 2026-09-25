import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import 'listing_type_badge.dart';

class ListingImage extends StatelessWidget {
  const ListingImage({
    super.key,
    required this.food,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.iconSize = 36,
    this.showTypeBadge = false,
  });

  final FoodItem food;
  final double? width;
  final double? height;
  final double borderRadius;
  final double iconSize;
  final bool showTypeBadge;

  @override
  Widget build(BuildContext context) {
    final imageUrl = food.imageUrl?.trim();
    final hasUrl = imageUrl != null && imageUrl.isNotEmpty && imageUrl != 'null';
    final isAsset = hasUrl &&
        (imageUrl.startsWith('asset:') ||
            imageUrl.startsWith('assets/') ||
            imageUrl.startsWith('pics/'));
    final assetPath =
        isAsset && imageUrl.startsWith('asset:') ? imageUrl.substring(6) : imageUrl;
    final resolvedUrl = !isAsset && hasUrl
        ? ApiService.imageUrl(imageUrl, cacheKey: food.imageCacheKey)
        : null;

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width,
        height: height,
        color: food.bgColor,
        child: isAsset
            ? Image.asset(
                assetPath!,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _iconFallback(),
              )
            : resolvedUrl != null
                ? Image.network(
                    resolvedUrl,
                    key: ValueKey(
                      '${food.id}|$resolvedUrl|${food.imageCacheKey ?? ''}',
                    ),
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    gaplessPlayback: false,
                    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    errorBuilder: (_, _, _) => _iconFallback(),
                  )
                : _iconFallback(),
      ),
    );

    if (!showTypeBadge) return image;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(child: image),
          Positioned(
            left: 6,
            top: 6,
            right: 6,
            child: Align(
              alignment: Alignment.topLeft,
              child: ListingTypeBadge(food: food, compact: true),
            ),
          ),
        ],
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
