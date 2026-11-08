import 'package:flutter/foundation.dart';

import 'storefront_host_hostname.dart';

/// Detects branded kitchen hosts and paths on web, e.g. puran.societyeats.com.
class StorefrontHost {
  StorefrontHost._();

  static const _reservedSubdomains = {
    'www',
    'app',
    'api',
    'admin',
  };

  /// Apex used to read kitchen subdomains, e.g. `puran.societyeats.com` → puran.
  static const apexDomain = String.fromEnvironment(
    'STOREFRONT_APEX_DOMAIN',
    defaultValue: 'societyeats.com',
  );

  /// Local dev: `flutter run -d chrome --dart-define=STOREFRONT_DEV_SLUG=puran`
  static const devSlug = String.fromEnvironment(
    'STOREFRONT_DEV_SLUG',
    defaultValue: '',
  );

  static String? kitchenSlugFromUri(Uri uri) {
    final fromDev = devSlug.trim().toLowerCase();
    final host = _effectiveWebHost(uri);
    if (kIsWeb && fromDev.isNotEmpty && _looksLikeLocalDev(host)) {
      return _normalizeSlug(fromDev);
    }

    final pathSlug = _slugFromPath(uri);
    if (pathSlug != null) return pathSlug;

    return _slugFromHost(host);
  }

  static String _effectiveWebHost(Uri uri) {
    if (kIsWeb) {
      final live = liveWebHostname().trim().toLowerCase();
      if (live.isNotEmpty) return live;
    }
    return uri.host.trim().toLowerCase();
  }

  static bool _looksLikeLocalDev(String host) {
    final lower = host.toLowerCase();
    return lower == 'localhost' ||
        lower.startsWith('127.') ||
        lower.endsWith('.localhost');
  }

  static String? _slugFromPath(Uri uri) {
    final segments =
        uri.pathSegments.where((segment) => segment.trim().isNotEmpty).toList();
    if (segments.length < 2) return null;
    if (segments.first.toLowerCase() != 'kitchen') return null;
    return _normalizeSlug(segments[1]);
  }

  static String? _slugFromHost(String host) {
    final lower = host.trim().toLowerCase();
    if (lower.isEmpty || _looksLikeLocalDev(lower)) return null;

    final apex = apexDomain.trim().toLowerCase();
    if (apex.isNotEmpty && lower.endsWith('.$apex')) {
      final prefix = lower.substring(0, lower.length - apex.length - 1);
      if (prefix.isEmpty || _reservedSubdomains.contains(prefix)) return null;
      final leaf = prefix.contains('.') ? prefix.split('.').last : prefix;
      if (_reservedSubdomains.contains(leaf)) return null;
      return _normalizeSlug(leaf);
    }

    final parts = lower.split('.');
    if (parts.length < 3) return null;

    final sub = parts.first;
    if (_reservedSubdomains.contains(sub)) return null;
    return _normalizeSlug(sub);
  }

  static String? _normalizeSlug(String raw) {
    final slug = raw.trim().toLowerCase();
    if (slug.length < 2) return null;
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,28}[a-z0-9])?$').hasMatch(slug)) {
      return null;
    }
    return slug;
  }
}
