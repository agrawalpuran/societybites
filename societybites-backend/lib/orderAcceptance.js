const { isMadeToOrderListing } = require("./listingAvailability");

/**
 * Regular ready-now orders skip seller acceptance. The listing already states
 * the stock and the availability window, so a second confirmation adds nothing
 * and only leaves the buyer waiting on a seller who may be away from the phone.
 * Made to Order and pre-orders still need the seller to agree before anything
 * is cooked.
 */
function skipsSellerAcceptance({ orderType, listings }) {
  if ((orderType || "regular") !== "regular") return false;
  return !(listings || []).some((listing) => isMadeToOrderListing(listing));
}

/** Same rule for an order loaded with its items and listings included. */
function orderSkipsSellerAcceptance(order) {
  if (!order) return false;
  return skipsSellerAcceptance({
    orderType: order.type,
    listings: (order.items || []).map((item) => item.listing),
  });
}

/**
 * Whether the seller can still decline with Can't fulfil. Auto-accepted orders
 * never had a seller press Accept, so the escape stays open until they mark the
 * order ready. Orders a seller did accept keep the original pending-only rule.
 */
function sellerCanDecline(order) {
  if (!order) return false;
  if (orderSkipsSellerAcceptance(order)) {
    return order.status === "pending" || order.status === "accepted";
  }
  return order.status === "pending";
}

module.exports = {
  skipsSellerAcceptance,
  orderSkipsSellerAcceptance,
  sellerCanDecline,
};
