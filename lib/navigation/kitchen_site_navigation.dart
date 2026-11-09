import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/main_shell_screen.dart';
import '../screens/onboarding_intent_screen.dart';
import '../screens/seller_kitchen_site_screen.dart';
import '../services/storefront_host.dart';

/// Keeps branded kitchen hosts on the seller site after login, checkout, etc.
class KitchenSiteNavigation {
  KitchenSiteNavigation._();

  static const _prefsKey = 'kitchen_site_context_slug_v1';
  static String? _heldSlug;

  /// Restore slug saved before login (URL often drops `/kitchen/{slug}` mid-flow).
  static Future<void> warmHeldSlug() async {
    if (_heldSlug != null && _heldSlug!.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey)?.trim().toLowerCase();
    if (saved != null && saved.isNotEmpty) {
      _heldSlug = saved;
    }
  }

  static Future<void> holdKitchenSlug(String slug) async {
    final normalized = slug.trim().toLowerCase();
    if (normalized.isEmpty) return;
    _heldSlug = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalized);
  }

  static String? activeKitchenSlug() {
    final fromUri = StorefrontHost.kitchenSlugFromUri(Uri.base);
    if (fromUri != null && fromUri.isNotEmpty) {
      _heldSlug = fromUri;
      return fromUri;
    }
    final held = _heldSlug?.trim();
    if (held != null && held.isNotEmpty) return held;
    return null;
  }

  static bool get isKitchenSiteContext {
    final slug = activeKitchenSlug();
    return slug != null && slug.isNotEmpty;
  }

  static Widget postAuthRoot({required bool hasSocietyFlat}) {
    if (!hasSocietyFlat) {
      return const OnboardingIntentScreen();
    }
    final slug = activeKitchenSlug();
    if (slug != null) {
      return SellerKitchenSiteScreen(slug: slug);
    }
    return const MainShellScreen();
  }

  static void replaceWithPostAuthRoot(
    BuildContext context, {
    required bool hasSocietyFlat,
  }) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => postAuthRoot(hasSocietyFlat: hasSocietyFlat),
      ),
      (_) => false,
    );
  }

  static void replaceWithKitchenSiteOrShell(
    BuildContext context, {
    int shellTabIndex = 0,
  }) {
    final slug = activeKitchenSlug();
    if (slug != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => SellerKitchenSiteScreen(slug: slug)),
        (_) => false,
      );
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => MainShellScreen(initialIndex: shellTabIndex),
      ),
      (_) => false,
    );
  }
}
