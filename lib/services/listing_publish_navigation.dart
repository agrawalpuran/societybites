import 'package:flutter/material.dart';

import 'my_listings_cache.dart';

/// After a seller publishes a new listing or pre-order campaign, return to Home
/// and refresh marketplace data without leaving the type-picker on screen.
class ListingPublishNavigation {
  ListingPublishNavigation._();

  static VoidCallback? onPublished;

  static void completeNewListing(BuildContext context) {
    MyListingsCache.clear();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    onPublished?.call();
  }
}
