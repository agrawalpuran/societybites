import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/selling_reach.dart';

/// Last successful home marketplace payload for stale-while-revalidate open.
class HomeFeedSnapshot {
  const HomeFeedSnapshot({
    required this.societyId,
    required this.listingMaps,
    required this.cityReach,
    required this.savedAt,
  });

  final String societyId;
  final List<Map<String, dynamic>> listingMaps;
  final SellingReach cityReach;
  final DateTime savedAt;
}

class HomeFeedCache {
  HomeFeedCache._();

  static const _keyPrefix = 'home_feed_cache_v1_';

  static String _storageKey(String societyId) => '$_keyPrefix$societyId';

  static Future<void> save({
    required String societyId,
    required List<Map<String, dynamic>> listingMaps,
    required SellingReach cityReach,
  }) async {
    if (societyId.isEmpty || listingMaps.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'societyId': societyId,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'listings': listingMaps,
      'cityReach': {
        'cityKey': cityReach.cityKey,
        'nearbyRadiusKm': cityReach.nearbyRadiusKm,
        'extendedRadiusKm': cityReach.extendedRadiusKm,
      },
    });
    await prefs.setString(_storageKey(societyId), payload);
  }

  static Future<HomeFeedSnapshot?> load(String societyId) async {
    if (societyId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(societyId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['societyId']?.toString() != societyId) return null;
      final listingsRaw = map['listings'];
      if (listingsRaw is! List || listingsRaw.isEmpty) return null;
      final listingMaps = listingsRaw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (listingMaps.isEmpty) return null;
      final reachRaw = map['cityReach'];
      final cityReach = reachRaw is Map
          ? SellingReach.fromJson(Map<String, dynamic>.from(reachRaw))
          : const SellingReach();
      final savedAt =
          DateTime.tryParse(map['savedAt']?.toString() ?? '') ?? DateTime.now();
      return HomeFeedSnapshot(
        societyId: societyId,
        listingMaps: listingMaps,
        cityReach: cityReach,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Drops cached feeds for other societies after the buyer joins a new one.
  static Future<void> retainOnly(String societyId) async {
    final prefs = await SharedPreferences.getInstance();
    final keep = _storageKey(societyId);
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_keyPrefix) && key != keep) {
        await prefs.remove(key);
      }
    }
  }
}
