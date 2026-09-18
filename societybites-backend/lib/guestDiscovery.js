const prisma = require("./prisma");
const { listingCategoriesFromRecord } = require("../utils/listingCategories");
const { canonicalCityKey } = require("./launchCity");
const { expireDueListings } = require("../utils/listingExpiry");

const GUEST_REACH_LEVELS = ["NEARBY", "EXTENDED"];

const ACTIVE_REGULAR_LISTING_WHERE = {
  status: "active",
  campaignId: null,
  catalogType: "REGULAR",
};

const listingInclude = {
  reviews: {
    select: { rating: true },
  },
};

function displayCityName(cityKey) {
  if (cityKey === "bengaluru") return "Bengaluru";
  if (!cityKey) return "Bengaluru";
  return cityKey.charAt(0).toUpperCase() + cityKey.slice(1);
}

function requestedCityKey(query) {
  const raw = query && (query.city || query.cityKey);
  const canonical = canonicalCityKey(raw || "bengaluru");
  return canonical || "bengaluru";
}

function serializeGuestListing(listing, seller) {
  const reviews = listing.reviews || [];
  const reviewCount = reviews.length;
  const avgRating =
    reviewCount > 0
      ? reviews.reduce((sum, review) => sum + review.rating, 0) / reviewCount
      : 0;

  return {
    id: listing.id,
    name: listing.name,
    description: listing.description,
    price: listing.price,
    quantity: listing.quantity,
    availableAt: listing.availableAt,
    imageUrl: listing.imageUrl,
    weightUnit: listing.weightUnit,
    weightValue: listing.weightValue,
    tags: listing.tags || [],
    foodType: listing.foodType || null,
    category: listingCategoriesFromRecord(listing)[0] || listing.category || null,
    categories: listingCategoriesFromRecord(listing),
    status: listing.status,
    catalogType: listing.catalogType || "REGULAR",
    sellerId: listing.sellerId,
    sellerName: (seller && seller.name) || "Neighbor",
    avgRating: Math.round(avgRating * 10) / 10,
    reviewCount,
  };
}

function serializeGuestKitchen(seller) {
  const listings = (seller.listings || []).map((listing) =>
    serializeGuestListing(listing, seller)
  );
  const categories = [
    ...new Set(listings.flatMap((item) => item.categories || []).filter(Boolean)),
  ];
  return {
    seller: {
      id: seller.id,
      name: seller.name || "Neighbor",
      societyName: (seller.society && seller.society.name) || null,
      categories,
    },
    listings,
  };
}

function matchesGuestEligibility(seller, cityKey) {
  if (!seller) return false;
  if (!["seller", "super_admin"].includes(seller.role || "")) return false;
  if (!GUEST_REACH_LEVELS.includes(seller.sellingReachLevel || "")) return false;
  if (canonicalCityKey(seller.society && seller.society.city) !== cityKey) {
    return false;
  }
  return Array.isArray(seller.listings) && seller.listings.length > 0;
}

async function societyIdsForCity(cityKey) {
  const societies = await prisma.society.findMany({
    select: { id: true, city: true },
  });
  return societies
    .filter((society) => canonicalCityKey(society.city) === cityKey)
    .map((society) => society.id);
}

async function discoverGuestKitchens({ query } = {}) {
  const cityKey = requestedCityKey(query);
  await expireDueListings(prisma);

  const societyIds = await societyIdsForCity(cityKey);
  if (societyIds.length === 0) {
    return {
      cityKey,
      cityName: displayCityName(cityKey),
      kitchens: [],
    };
  }

  const sellers = await prisma.user.findMany({
    where: {
      role: { in: ["seller", "super_admin"] },
      sellingReachLevel: { in: GUEST_REACH_LEVELS },
      societyId: { in: societyIds },
      listings: { some: ACTIVE_REGULAR_LISTING_WHERE },
    },
    include: {
      society: { select: { id: true, name: true, city: true } },
      listings: {
        where: ACTIVE_REGULAR_LISTING_WHERE,
        include: listingInclude,
        orderBy: { createdAt: "desc" },
      },
    },
    orderBy: { name: "asc" },
  });

  const kitchens = sellers
    .filter((seller) => matchesGuestEligibility(seller, cityKey))
    .map(serializeGuestKitchen);

  return {
    cityKey,
    cityName: displayCityName(cityKey),
    kitchens,
  };
}

async function getGuestKitchenStorefront({ sellerId, query } = {}) {
  const cityKey = requestedCityKey(query);
  await expireDueListings(prisma, { sellerId: String(sellerId) });

  const seller = await prisma.user.findUnique({
    where: { id: String(sellerId) },
    include: {
      society: { select: { id: true, name: true, city: true } },
      listings: {
        where: ACTIVE_REGULAR_LISTING_WHERE,
        include: listingInclude,
        orderBy: { createdAt: "desc" },
      },
    },
  });

  if (!matchesGuestEligibility(seller, cityKey)) {
    const err = new Error("Kitchen not found");
    err.statusCode = 404;
    throw err;
  }

  return {
    cityKey,
    cityName: displayCityName(cityKey),
    ...serializeGuestKitchen(seller),
  };
}

module.exports = {
  GUEST_REACH_LEVELS,
  ACTIVE_REGULAR_LISTING_WHERE,
  discoverGuestKitchens,
  getGuestKitchenStorefront,
  serializeGuestListing,
};
