const { canonicalCityKey } = require("./launchCity");
const { distanceKmBetweenCoordinates, isValidSocietyLocation } = require("./geoDistance");
const {
  SELLING_REACH_LEVELS,
  DEFAULT_SELLING_REACH_LEVEL,
  normalizeSellingReachLevel,
  serializeSellingReach,
} = require("./sellingReach");

/**
 * MVP: a seller is only discoverable to buyers in the same canonical city.
 * Geographic closeness across cities is not enough.
 */
function sameCanonicalCity(buyerSociety, sellerSociety) {
  const buyerCity = canonicalCityKey(buyerSociety && buyerSociety.city);
  const sellerCity = canonicalCityKey(sellerSociety && sellerSociety.city);
  return Boolean(buyerCity && sellerCity && buyerCity === sellerCity);
}

function sameSociety(buyerSociety, sellerSociety) {
  const buyerId = buyerSociety && buyerSociety.id;
  const sellerId = sellerSociety && sellerSociety.id;
  return Boolean(buyerId && sellerId && buyerId === sellerId);
}

/**
 * Backend-authoritative discovery eligibility for a future Explore Nearby surface.
 * Does not change GET /listings. Client radius/distance fields are ignored.
 *
 * @returns {{
 *   eligible: boolean,
 *   reason: string,
 *   distanceKm: number|null,
 *   cityKey: string|null,
 *   appliedRadiusKm: number|null
 * }}
 */
function evaluateSellerDiscoveryEligibility({
  buyerSociety,
  sellerSociety,
  sellingReachLevel,
  cityReachConfig,
  nearbyRadiusKm: _clientNearbyRadiusKm,
  extendedRadiusKm: _clientExtendedRadiusKm,
  distanceKm: _clientDistanceKm,
} = {}) {
  void _clientNearbyRadiusKm;
  void _clientExtendedRadiusKm;
  void _clientDistanceKm;
  const level = normalizeSellingReachLevel(sellingReachLevel);

  if (sameSociety(buyerSociety, sellerSociety)) {
    return {
      eligible: true,
      reason: "SAME_SOCIETY",
      distanceKm: 0,
      cityKey: canonicalCityKey(sellerSociety && sellerSociety.city) || null,
      appliedRadiusKm: null,
    };
  }

  if (level === SELLING_REACH_LEVELS.MY_SOCIETY || !level) {
    return {
      eligible: false,
      reason: "MY_SOCIETY_ONLY",
      distanceKm: null,
      cityKey: canonicalCityKey(sellerSociety && sellerSociety.city) || null,
      appliedRadiusKm: null,
    };
  }

  if (!sameCanonicalCity(buyerSociety, sellerSociety)) {
    return {
      eligible: false,
      reason: "DIFFERENT_CITY",
      distanceKm: null,
      cityKey: canonicalCityKey(sellerSociety && sellerSociety.city) || null,
      appliedRadiusKm: null,
    };
  }

  const cityKey = canonicalCityKey(sellerSociety && sellerSociety.city) || null;
  const reach = serializeSellingReach(sellerSociety && sellerSociety.city, cityReachConfig);

  let appliedRadiusKm = null;
  if (level === SELLING_REACH_LEVELS.NEARBY) appliedRadiusKm = reach.nearbyRadiusKm;
  if (level === SELLING_REACH_LEVELS.EXTENDED) appliedRadiusKm = reach.extendedRadiusKm;

  if (appliedRadiusKm == null) {
    return {
      eligible: false,
      reason: "CITY_CONFIG_MISSING",
      distanceKm: null,
      cityKey,
      appliedRadiusKm: null,
    };
  }

  if (!isValidSocietyLocation(sellerSociety)) {
    return {
      eligible: false,
      reason: "SELLER_COORDINATES_MISSING",
      distanceKm: null,
      cityKey,
      appliedRadiusKm,
    };
  }

  if (!isValidSocietyLocation(buyerSociety)) {
    return {
      eligible: false,
      reason: "BUYER_COORDINATES_MISSING",
      distanceKm: null,
      cityKey,
      appliedRadiusKm,
    };
  }

  const distanceKm = distanceKmBetweenCoordinates(buyerSociety, sellerSociety);
  if (distanceKm == null) {
    return {
      eligible: false,
      reason: "DISTANCE_UNAVAILABLE",
      distanceKm: null,
      cityKey,
      appliedRadiusKm,
    };
  }

  if (distanceKm <= appliedRadiusKm) {
    return {
      eligible: true,
      reason: level === SELLING_REACH_LEVELS.NEARBY ? "WITHIN_NEARBY" : "WITHIN_EXTENDED",
      distanceKm,
      cityKey,
      appliedRadiusKm,
    };
  }

  return {
    eligible: false,
    reason: level === SELLING_REACH_LEVELS.NEARBY ? "OUTSIDE_NEARBY" : "OUTSIDE_EXTENDED",
    distanceKm,
    cityKey,
    appliedRadiusKm,
  };
}

function isSellerDiscoverableByBuyer(input) {
  return evaluateSellerDiscoveryEligibility(input).eligible;
}

/** Home grouping uses distance vs nearby radius, not the seller's opted-in level. */
function discoveryDisplayReach(eligibility, nearbyRadiusKm) {
  if (!eligibility || !eligibility.eligible) return null;
  if (eligibility.reason === "SAME_SOCIETY") return "inSociety";
  if (eligibility.distanceKm != null && nearbyRadiusKm != null) {
    return eligibility.distanceKm <= nearbyRadiusKm ? "nearby" : "extended";
  }
  if (eligibility.reason === "WITHIN_NEARBY") return "nearby";
  return "extended";
}

module.exports = {
  sameSociety,
  sameCanonicalCity,
  evaluateSellerDiscoveryEligibility,
  isSellerDiscoverableByBuyer,
  discoveryDisplayReach,
  DEFAULT_SELLING_REACH_LEVEL,
};
