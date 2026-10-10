import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';

const _maxHomePrecache = 14;

/// Warms the image cache for the first visible home cards (network + assets).
Future<void> precacheHomeListingImages(
  BuildContext context,
  List<FoodItem> listings, {
  int maxCount = _maxHomePrecache,
}) async {
  if (!context.mounted || listings.isEmpty) return;

  var warmed = 0;
  for (final food in listings) {
    if (warmed >= maxCount) break;
    final raw = food.imageUrl?.trim();
    if (raw == null || raw.isEmpty || raw == 'null') continue;

    final isAsset = raw.startsWith('asset:') ||
        raw.startsWith('assets/') ||
        raw.startsWith('pics/');
    if (isAsset) {
      final path = raw.startsWith('asset:') ? raw.substring(6) : raw;
      await precacheImage(AssetImage(path), context).catchError((_) {});
      warmed++;
      continue;
    }

    final resolved = ApiService.imageUrl(raw, cacheKey: food.imageCacheKey);
    await precacheImage(NetworkImage(resolved), context).catchError((_) {});
    warmed++;
  }
}
