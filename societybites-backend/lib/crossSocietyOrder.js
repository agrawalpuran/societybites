const prisma = require("./prisma");
const { canonicalCityKey } = require("./launchCity");
const { evaluateSellerDiscoveryEligibility } = require("./sellingReachEligibility");
const { FULFILMENT_MODES, offersSellerDelivery } = require("./sellerFulfilment");

const ORDER_FULFILMENT = Object.freeze({
  PICKUP: "pickup",
  SELLER_DELIVERY: "seller_delivery",
});

function httpError(statusCode, message, code) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (code) err.code = code;
  return err;
}

function notEligibleError() {
  return httpError(
    400,
    "This seller is no longer available for delivery to your society.",
    "SELLER_NOT_ELIGIBLE"
  );
}

function normalizeRequestedFulfilment(value) {
  if (value == null || value === "") return null;
  const raw = String(value).trim().toLowerCase();
  if (raw === "pickup" || raw === "buyer_pickup") return ORDER_FULFILMENT.PICKUP;
  if (raw === "seller_delivery") return ORDER_FULFILMENT.SELLER_DELIVERY;
  throw httpError(400, "This delivery option is no longer available.", "FULFILMENT_INVALID");
}

function allowedOrderFulfilmentMethods(sellerMode) {
  const mode = sellerMode || FULFILMENT_MODES.BUYER_PICKUP;
  if (mode === FULFILMENT_MODES.SELLER_DELIVERY) {
    return [ORDER_FULFILMENT.SELLER_DELIVERY];
  }
  if (mode === FULFILMENT_MODES.BOTH) {
    return [ORDER_FULFILMENT.PICKUP, ORDER_FULFILMENT.SELLER_DELIVERY];
  }
  return [ORDER_FULFILMENT.PICKUP];
}

function snapshotRegularFulfilment({ seller, requestedMethod }) {
  const allowed = allowedOrderFulfilmentMethods(seller && seller.fulfilmentMode);
  let method = normalizeRequestedFulfilment(requestedMethod);
  if (!method) {
    if (allowed.length === 1) {
      method = allowed[0];
    } else {
      throw httpError(
        400,
        "Please choose how you would like to receive your order.",
        "FULFILMENT_REQUIRED"
      );
    }
  }
  if (!allowed.includes(method)) {
    throw httpError(400, "This delivery option is no longer available.", "FULFILMENT_UNAVAILABLE");
  }
  const deliveryCharge =
    method === ORDER_FULFILMENT.SELLER_DELIVERY && offersSellerDelivery(seller && seller.fulfilmentMode)
      ? Number(seller && seller.deliveryCharge) || 0
      : 0;
  return { fulfilmentMethod: method, deliveryCharge };
}

async function authorizeListingForBuyer({ buyer, listing, clientRadiusKm, clientDistanceKm }) {
  void clientRadiusKm;
  void clientDistanceKm;
  if (!buyer || !buyer.societyId) {
    throw httpError(400, "You must join a society before placing orders", "SOCIETY_REQUIRED");
  }
  if (listing.societyId === buyer.societyId) {
    return { crossSociety: false };
  }

  const seller = await prisma.user.findUnique({
    where: { id: listing.sellerId },
    include: { society: true },
  });
  if (!seller || !["seller", "super_admin"].includes(seller.role || "")) {
    throw httpError(400, "This seller is currently unavailable.", "SELLER_UNAVAILABLE");
  }
  if (!seller.societyId || listing.societyId !== seller.societyId) {
    throw notEligibleError();
  }

  let buyerSociety = buyer.society;
  if (!buyerSociety || !buyerSociety.id) {
    buyerSociety = await prisma.society.findUnique({ where: { id: buyer.societyId } });
  }
  if (!buyerSociety || !seller.society) {
    throw notEligibleError();
  }

  const cityKey = canonicalCityKey(buyerSociety.city);
  const config = cityKey
    ? await prisma.cityReachConfig.findUnique({ where: { cityKey } })
    : null;

  const eligibility = evaluateSellerDiscoveryEligibility({
    buyerSociety,
    sellerSociety: seller.society,
    sellingReachLevel: seller.sellingReachLevel,
    cityReachConfig: config,
    nearbyRadiusKm: clientRadiusKm,
    distanceKm: clientDistanceKm,
  });

  if (!eligibility.eligible) {
    throw notEligibleError();
  }

  return {
    crossSociety: true,
    seller,
    buyerSociety,
    eligibility,
  };
}

module.exports = {
  ORDER_FULFILMENT,
  authorizeListingForBuyer,
  snapshotRegularFulfilment,
  normalizeRequestedFulfilment,
  allowedOrderFulfilmentMethods,
};
