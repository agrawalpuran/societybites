import 'package:flutter/material.dart';

import '../models/data.dart';
import '../screens/home_listing_filter.dart';
import '../services/api_service.dart';

/// First-screen listing photos only; full feed still loads on scroll.
const homePrecacheMaxCount = 8;

/// Warms the image cache for eligible home cards (network + assets).
Future<void> precacheHomeListingImages(
  BuildContext context,
  List<FoodItem> listings, {
  int maxCount = homePrecacheMaxCount,
  String? buyerSocietyId,
  Set<String>? warmedUrls,
}) async {
  if (!context.mounted || listings.isEmpty) return;

  final eligible = applyHomeListingFilters(
    listings,
    buyerSocietyId: buyerSocietyId,
    excludeFssaiBlockedFromBuyerFeed: true,
  );
  if (eligible.isEmpty) return;

  var warmed = 0;
  for (final food in eligible) {
    if (warmed >= maxCount) break;
    final raw = food.imageUrl?.trim();
    if (raw == null || raw.isEmpty || raw == 'null') continue;

    final isAsset = raw.startsWith('asset:') ||
        raw.startsWith('assets/') ||
        raw.startsWith('pics/');
    if (isAsset) {
      final path = raw.startsWith('asset:') ? raw.substring(6) : raw;
      final assetKey = 'asset:$path';
      if (warmedUrls != null && warmedUrls.contains(assetKey)) continue;
      await precacheImage(AssetImage(path), context).catchError((_) {});
      if (!context.mounted) return;
      warmedUrls?.add(assetKey);
      warmed++;
      continue;
    }

    final resolved = ApiService.imageUrl(raw, cacheKey: food.imageCacheKey);
    if (warmedUrls != null && warmedUrls.contains(resolved)) continue;
    await precacheImage(NetworkImage(resolved), context).catchError((_) {});
    if (!context.mounted) return;
    warmedUrls?.add(resolved);
    warmed++;
  }
}
