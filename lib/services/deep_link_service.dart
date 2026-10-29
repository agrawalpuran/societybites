import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web share / deep-link targets. Mobile ignores URL capture for MVP.
enum DeepLinkKind { seller, campaign, listing }

class DeepLinkTarget {
  const DeepLinkTarget({required this.kind, required this.id});

  final DeepLinkKind kind;
  final String id;

  String get storageValue => '${kind.name}:$id';

  static DeepLinkTarget? tryParseStorage(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final sep = text.indexOf(':');
    if (sep <= 0 || sep >= text.length - 1) return null;
    final kindName = text.substring(0, sep);
    final id = text.substring(sep + 1).trim();
    if (id.isEmpty) return null;
    DeepLinkKind? kind;
    for (final value in DeepLinkKind.values) {
      if (value.name == kindName) {
        kind = value;
        break;
      }
    }
    if (kind == null) return null;
    return DeepLinkTarget(kind: kind, id: id);
  }
}

/// Captures `/s/:id`, `/c/:id`, `/l/:id` (and query fallbacks), holds them across login.
class DeepLinkService {
  DeepLinkService._();

  static const prefsKey = 'pending_deep_link_v1';

  /// Production web origin when sharing from the native app.
  /// Override with `--dart-define=WEB_BASE_URL=https://...`.
  static const defaultWebBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://societyeats.vercel.app',
  );

  static DeepLinkTarget? _memory;
  static bool _handledThisSession = false;

  @visibleForTesting
  static void resetForTest() {
    _memory = null;
    _handledThisSession = false;
  }

  /// Prefer path segments; also accept hash routes and `?s=` / `?c=` query.
  static DeepLinkTarget? parseUri(Uri uri) {
    final effective = _effectiveUri(uri);
    final segments =
        effective.pathSegments.where((s) => s.trim().isNotEmpty).toList();

    if (segments.length >= 2) {
      final head = segments[0].toLowerCase();
      final id = segments[1].trim();
      if (id.isNotEmpty) {
        if (head == 's' || head == 'seller') {
          return DeepLinkTarget(kind: DeepLinkKind.seller, id: id);
        }
        if (head == 'c' || head == 'campaign' || head == 'preorder') {
          return DeepLinkTarget(kind: DeepLinkKind.campaign, id: id);
        }
        if (head == 'l' || head == 'listing' || head == 'dish') {
          return DeepLinkTarget(kind: DeepLinkKind.listing, id: id);
        }
      }
    }

    final params = effective.queryParameters;
    final sellerId =
        (params['s'] ?? params['seller'] ?? params['sellerId'])?.trim();
    if (sellerId != null && sellerId.isNotEmpty) {
      return DeepLinkTarget(kind: DeepLinkKind.seller, id: sellerId);
    }
    final campaignId =
        (params['c'] ?? params['campaign'] ?? params['campaignId'])?.trim();
    if (campaignId != null && campaignId.isNotEmpty) {
      return DeepLinkTarget(kind: DeepLinkKind.campaign, id: campaignId);
    }
    final listingId =
        (params['l'] ?? params['listing'] ?? params['listingId'])?.trim();
    if (listingId != null && listingId.isNotEmpty) {
      return DeepLinkTarget(kind: DeepLinkKind.listing, id: listingId);
    }
    return null;
  }

  static Uri _effectiveUri(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.startsWith('/')) {
      return uri.replace(path: fragment, fragment: '');
    }
    return uri;
  }

  static String webBaseUrl() {
    if (kIsWeb) {
      final origin = Uri.base.origin.trim();
      if (origin.isNotEmpty && origin != 'null') return origin;
    }
    return defaultWebBaseUrl.replaceAll(RegExp(r'/$'), '');
  }

  static String sellerShareUrl(String sellerId) {
    final id = sellerId.trim();
    return '${webBaseUrl()}/s/${Uri.encodeComponent(id)}';
  }

  static String campaignShareUrl(String campaignId) {
    final id = campaignId.trim();
    return '${webBaseUrl()}/c/${Uri.encodeComponent(id)}';
  }

  static String listingShareUrl(String listingId) {
    final id = listingId.trim();
    return '${webBaseUrl()}/l/${Uri.encodeComponent(id)}';
  }

  static Future<void> captureFromUri(Uri uri) async {
    final target = parseUri(uri);
    if (target == null) return;
    await savePending(target);
  }

  /// Web startup: read the browser URL once.
  static Future<void> captureBrowserUrlIfWeb() async {
    if (!kIsWeb) return;
    await captureFromUri(Uri.base);
  }

  static Future<void> savePending(DeepLinkTarget target) async {
    _memory = target;
    _handledThisSession = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, target.storageValue);
  }

  static Future<DeepLinkTarget?> peekPending() async {
    if (_memory != null) return _memory;
    final prefs = await SharedPreferences.getInstance();
    final parsed = DeepLinkTarget.tryParseStorage(prefs.getString(prefsKey));
    _memory = parsed;
    return parsed;
  }

  static Future<DeepLinkTarget?> consumePending() async {
    if (_handledThisSession) return null;
    final target = await peekPending();
    if (target == null) return null;
    _handledThisSession = true;
    _memory = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    return target;
  }

  static Future<void> clearPending() async {
    _memory = null;
    _handledThisSession = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}
