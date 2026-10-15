const MY_HOME_VERIFIED = "my home (verified)";

/** Flat is revealed only after the seller has confirmed the order (not while pending). */
const BUYER_PICKUP_ORDER_STATUSES = new Set([
  "accepted",
  "preparing",
  "ready",
  "picked_up",
  "completed",
]);

function sellerHidesFlatNumber(user) {
  return Boolean(user && user.hideFlatNumber);
}

function normalizePickupLocation(value) {
  return String(value || "").trim().toLowerCase();
}

function isMyHomeVerifiedPickup(location) {
  const norm = normalizePickupLocation(location);
  if (!norm) return false;
  if (norm === MY_HOME_VERIFIED) return true;
  return norm.includes("my home") && norm.includes("verified");
}

function isBuyerPickupFulfilment(method) {
  const norm = String(method || "pickup").trim().toLowerCase();
  return norm === "pickup" || norm === "buyer_pickup";
}

function parseHideFlatNumber(value) {
  if (value === undefined || value === null) return undefined;
  if (typeof value === "boolean") return value;
  if (value === "true" || value === "yes" || value === "1" || value === 1) return true;
  if (value === "false" || value === "no" || value === "0" || value === 0) return false;
  return undefined;
}

function buyerMaySeeSellerFlat({ seller, viewerUserId, order, pickupLocation }) {
  if (!sellerHidesFlatNumber(seller)) return true;
  if (!viewerUserId || !order) return false;
  if (String(order.buyerId) !== String(viewerUserId)) return false;
  if (!BUYER_PICKUP_ORDER_STATUSES.has(String(order.status || ""))) return false;
  if (!isBuyerPickupFulfilment(order.fulfilmentMethod)) return false;
  const pickup = pickupLocation || order.pickupLocation;
  return isMyHomeVerifiedPickup(pickup);
}

function shouldExposeSellerFlatNumber({ seller, viewerUserId, order, pickupLocation }) {
  if (!seller) return true;
  if (!sellerHidesFlatNumber(seller)) return true;
  if (viewerUserId && String(seller.id) === String(viewerUserId)) return true;
  return buyerMaySeeSellerFlat({ seller, viewerUserId, order, pickupLocation });
}

function redactSellerFlatOnListingPayload(payload, context = {}) {
  if (!payload) return payload;
  const seller = context.seller || { id: payload.sellerId, hideFlatNumber: context.hideFlatNumber };
  const expose = shouldExposeSellerFlatNumber({
    seller,
    viewerUserId: context.viewerUserId,
    order: context.order,
    pickupLocation: context.pickupLocation || payload.pickupLocation,
  });
  if (expose) return payload;
  return { ...payload, flatNumber: null, block: null };
}

module.exports = {
  sellerHidesFlatNumber,
  parseHideFlatNumber,
  shouldExposeSellerFlatNumber,
  redactSellerFlatOnListingPayload,
  isMyHomeVerifiedPickup,
  isBuyerPickupFulfilment,
};
