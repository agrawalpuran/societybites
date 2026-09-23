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

    return ClipRRect(
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
