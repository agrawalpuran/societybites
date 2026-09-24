const prisma = require("./prisma");
const { canonicalCityKey } = require("./launchCity");
const { isValidSocietyLocation } = require("./geoDistance");
const { evaluateSellerDiscoveryEligibility } = require("./sellingReachEligibility");
const { serializeSellingReach } = require("./sellingReach");
const { serializeFulfilment } = require("./sellerFulfilment");
const { serializePaymentPreference } = require("./sellerPaymentPreference");
const { serializeListing, attachQuantitySold } = require("../utils/listingSerializer");
const { expireDueListings, DISCOVERABLE_STATUSES } = require("../utils/listingExpiry");

const ACTIVE_LISTING_WHERE = {
  status: { in: DISCOVERABLE_STATUSES },
  campaignId: null,
  catalogType: "REGULAR",
};

const listingInclude = {
  seller: {
    include: { flat: true },
  },
  reviews: {
    select: { rating: true },
  },
};

function roundKm(value) {
  if (!Number.isFinite(value)) return null;
  return Math.round(value * 10) / 10;
}

function appliedDisplayRadiusKm(reach) {
  const nearby = reach && Number.isFinite(reach.nearbyRadiusKm) ? reach.nearbyRadiusKm : null;
  const extended = reach && Number.isFinite(reach.extendedRadiusKm) ? reach.extendedRadiusKm : null;
  if (extended != null && nearby != null) return Math.max(nearby, extended);
  return extended != null ? extended : nearby;
}

function unavailablePayload({ reason, buyerSociety, reach }) {
  return {
    available: false,
    reason,
    buyerSocietyName: (buyerSociety && buyerSociety.name) || null,
    nearbyRadiusKm: reach ? reach.nearbyRadiusKm : null,
    extendedRadiusKm: reach ? reach.extendedRadiusKm : null,
    appliedRadiusKm: appliedDisplayRadiusKm(reach),
    sellers: [],
  };
}

async function loadBuyerSociety(buyer) {
  if (buyer && buyer.society && buyer.society.id) return buyer.society;
  if (!buyer || !buyer.societyId) return null;
  return prisma.society.findUnique({ where: { id: buyer.societyId } });
}

async function loadCityReachConfig(society) {
  const cityKey = canonicalCityKey(society && society.city);
  if (!cityKey) return { cityKey: null, config: null, reach: serializeSellingReach(society && society.city, null) };
  const config = await prisma.cityReachConfig.findUnique({ where: { cityKey } });
  return {
    cityKey,
    config,
    reach: serializeSellingReach(society && society.city, config),
  };
}

function serializeNearbySeller(seller, eligibility) {
  const listings = (seller.listings || []).map((listing) => serializeListing(listing));
  return {
    seller: {
      id: seller.id,
      name: seller.name || "Neighbor",
      societyId: seller.societyId || null,
      societyName: (seller.society && seller.society.name) || null,
      distanceKm: roundKm(eligibility.distanceKm),
      sellingReachLevel: seller.sellingReachLevel || "MY_SOCIETY",
      paymentPreference: serializePaymentPreference(seller),
    },
    fulfilment: serializeFulfilment(seller),
    paymentPreference: serializePaymentPreference(seller),
    listings,
  };
}

async function discoverNearbySellers({ buyer, query } = {}) {
  void query;
  const buyerSociety = await loadBuyerSociety(buyer);
  if (!buyerSociety) {
    return unavailablePayload({ reason: "BUYER_SOCIETY_MISSING", buyerSociety: null, reach: null });
  }

  const { config, reach } = await loadCityReachConfig(buyerSociety);

  if (!isValidSocietyLocation(buyerSociety)) {
    return unavailablePayload({
      reason: "BUYER_COORDINATES_MISSING",
      buyerSociety,
      reach: config ? reach : { ...reach, nearbyRadiusKm: null, extendedRadiusKm: null },
    });
  }

  if (!config) {
    return unavailablePayload({
      reason: "CITY_CONFIG_MISSING",
      buyerSociety,
      reach,
    });
  }

  await expireDueListings(prisma);

  const candidates = await prisma.user.findMany({
    where: {
      role: { in: ["seller", "super_admin"] },
      societyId: { not: null },
      listings: { some: ACTIVE_LISTING_WHERE },
    },
    include: {
      society: true,
      flat: true,
      listings: {
        where: ACTIVE_LISTING_WHERE,
        include: listingInclude,
        orderBy: { createdAt: "desc" },
      },
    },
  });

  await attachQuantitySold(
    prisma,
    candidates.flatMap((candidate) => candidate.listings || [])
  );

  const sellers = [];
  for (const candidate of candidates) {
    if (!candidate.listings || candidate.listings.length === 0) continue;
    const eligibility = evaluateSellerDiscoveryEligibility({
      buyerSociety,
      sellerSociety: candidate.society,
      sellingReachLevel: candidate.sellingReachLevel,
      cityReachConfig: config,
      nearbyRadiusKm: query && query.nearbyRadiusKm,
      extendedRadiusKm: query && query.extendedRadiusKm,
      distanceKm: query && query.distanceKm,
    });
    if (!eligibility.eligible) continue;
    sellers.push({
      card: serializeNearbySeller(candidate, eligibility),
      distanceKm: eligibility.distanceKm == null ? Number.POSITIVE_INFINITY : eligibility.distanceKm,
    });
  }

  sellers.sort((a, b) => a.distanceKm - b.distanceKm);

  return {
    available: true,
    reason: null,
    buyerSocietyName: buyerSociety.name || null,
    nearbyRadiusKm: reach.nearbyRadiusKm,
    extendedRadiusKm: reach.extendedRadiusKm,
    appliedRadiusKm: appliedDisplayRadiusKm(reach),
    sellers: sellers.map((item) => item.card),
  };
}

async function getNearbySellerStorefront({ buyer, sellerId, query } = {}) {
  void query;
  const buyerSociety = await loadBuyerSociety(buyer);
  if (!buyerSociety) {
    const err = new Error("You must join a society first");
    err.statusCode = 400;
    err.code = "SOCIETY_REQUIRED";
    throw err;
  }

  const { config } = await loadCityReachConfig(buyerSociety);
  if (!isValidSocietyLocation(buyerSociety) || !config) {
    const err = new Error("Nearby sellers are not available for your society yet.");
    err.statusCode = 404;
    err.code = "NEARBY_UNAVAILABLE";
    throw err;
  }

  await expireDueListings(prisma, { sellerId: String(sellerId) });

  const seller = await prisma.user.findUnique({
    where: { id: String(sellerId) },
    include: {
      society: true,
      flat: true,
      listings: {
        where: ACTIVE_LISTING_WHERE,
        include: listingInclude,
        orderBy: { createdAt: "desc" },
      },
    },
  });

  if (!seller || !["seller", "super_admin"].includes(seller.role || "")) {
    const err = new Error("Seller not found");
    err.statusCode = 404;
    throw err;
  }

  const eligibility = evaluateSellerDiscoveryEligibility({
    buyerSociety,
    sellerSociety: seller.society,
    sellingReachLevel: seller.sellingReachLevel,
    cityReachConfig: config,
    nearbyRadiusKm: query && query.nearbyRadiusKm,
    extendedRadiusKm: query && query.extendedRadiusKm,
    distanceKm: query && query.distanceKm,
  });

  if (!eligibility.eligible || !seller.listings || seller.listings.length === 0) {
    const err = new Error("Seller not found");
    err.statusCode = 404;
    throw err;
  }

  await attachQuantitySold(prisma, seller.listings);
  return serializeNearbySeller(seller, eligibility);
}

module.exports = {
  discoverNearbySellers,
  getNearbySellerStorefront,
};
