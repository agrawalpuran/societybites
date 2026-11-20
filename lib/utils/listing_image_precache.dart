import 'package:flutter/material.dart';

import '../models/data.dart';
import '../screens/home_listing_filter.dart';
import '../services/api_service.dart';

/// First-screen listing photos only; full feed still loads on scroll.
const homePrecacheMaxCount = 8;

/// How many of those photos start at once. The rest of the cap follows.
const homePrecacheBatchSize = 4;

/// Photos to warm, in the order the home screen shows them.
/// [priority] is the dishes already chosen for the first screen. When that
/// list is present, nothing below it is warmed, so off-screen dishes do not
/// take the connection. An empty [priority] falls back to the ranked feed.
List<FoodItem> homeListingImagesToWarm(
  List<FoodItem> listings, {
  List<FoodItem> priority = const [],
  int maxCount = homePrecacheMaxCount,
  String? buyerSocietyId,
}) {
  final ordered = <FoodItem>[];
  final seen = <String>{};

  void add(FoodItem food) {
    if (ordered.length >= maxCount) return;
    if (!seen.add(food.id)) return;
    final raw = food.imageUrl?.trim();
    if (raw == null || raw.isEmpty || raw == 'null') return;
    ordered.add(food);
  }

  for (final food in priority) {
    add(food);
  }
  if (priority.isEmpty) {
    final ranked = applyHomeListingFilters(
      listings,
      buyerSocietyId: buyerSocietyId,
      excludeFssaiBlockedFromBuyerFeed: true,
    );
    for (final food in ranked) {
      add(food);
    }
  }
  return ordered;
}

/// Warms the image cache for the first home cards (network + assets).
Future<void> precacheHomeListingImages(
  BuildContext context,
  List<FoodItem> listings, {
  List<FoodItem> priority = const [],
  int maxCount = homePrecacheMaxCount,
  String? buyerSocietyId,
  Set<String>? warmedUrls,
}) async {
  if (!context.mounted || (listings.isEmpty && priority.isEmpty)) return;

  final targets = homeListingImagesToWarm(
    listings,
    priority: priority,
    maxCount: maxCount,
    buyerSocietyId: buyerSocietyId,
  );
  for (var index = 0; index < targets.length; index += homePrecacheBatchSize) {
    if (!context.mounted) return;
    final end = index + homePrecacheBatchSize;
    final batch = targets.sublist(
      index,
      end > targets.length ? targets.length : end,
    );
    await Future.wait(
      batch.map((food) => _warmListingImage(context, food, warmedUrls)),
    );
  }
}

Future<void> _warmListingImage(
  BuildContext context,
  FoodItem food,
  Set<String>? warmedUrls,
) async {
  if (!context.mounted) return;
  final raw = food.imageUrl!.trim();
  final isAsset = raw.startsWith('asset:') ||
      raw.startsWith('assets/') ||
      raw.startsWith('pics/');
  if (isAsset) {
    final path = raw.startsWith('asset:') ? raw.substring(6) : raw;
    final assetKey = 'asset:$path';
    if (warmedUrls != null && warmedUrls.contains(assetKey)) return;
    await precacheImage(AssetImage(path), context).catchError((_) {});
    if (!context.mounted) return;
    warmedUrls?.add(assetKey);
    return;
  }

  final resolved = ApiService.imageUrl(raw, cacheKey: food.imageCacheKey);
  if (warmedUrls != null && warmedUrls.contains(resolved)) return;
  await precacheImage(NetworkImage(resolved), context).catchError((_) {});
  if (!context.mounted) return;
  warmedUrls?.add(resolved);
}
