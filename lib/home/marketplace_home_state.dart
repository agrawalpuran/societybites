/// Which home experience the loaded marketplace should show.
enum MarketplaceHomeState { discovery, growing, active }

/// Counts already visible to the buyer. Search and category filters are not included.
class MarketplaceMetrics {
  const MarketplaceMetrics({
    required this.activeSellerCount,
    required this.availableListingCount,
  });

  final int activeSellerCount;
  final int availableListingCount;
}

/// One place for the Active threshold. Discovery is always zero listings.
class MarketplaceHomeThresholds {
  const MarketplaceHomeThresholds({
    this.activeSellers = 5,
    this.availableListings = 20,
  });

  final int activeSellers;
  final int availableListings;

  static const standard = MarketplaceHomeThresholds();
}

/// Pure state choice. Active requires both thresholds.
MarketplaceHomeState resolveMarketplaceState(
  MarketplaceMetrics metrics, {
  MarketplaceHomeThresholds thresholds = MarketplaceHomeThresholds.standard,
}) {
  if (metrics.availableListingCount <= 0) {
    return MarketplaceHomeState.discovery;
  }
  if (metrics.activeSellerCount >= thresholds.activeSellers &&
      metrics.availableListingCount >= thresholds.availableListings) {
    return MarketplaceHomeState.active;
  }
  return MarketplaceHomeState.growing;
}
