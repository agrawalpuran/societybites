function listingOf(order) {
  const item = order && order.items && order.items[0];
  return item && item.listing ? item.listing : null;
}

function isOutsideSellerDelivery(order) {
  if (!order || (order.type || "regular") !== "regular") return false;
  const listing = listingOf(order);
  if (!listing || !listing.societyId || !order.societyId) return false;
  if (listing.societyId === order.societyId) return false;
  return String(order.fulfilmentMethod || "").toLowerCase() === "seller_delivery";
}

function isUpiFoodCashDeliverySplit(order) {
  return isOutsideSellerDelivery(order) && String(order.paymentMethod || "").toLowerCase() === "upi";
}

function isCodOutsideSellerDelivery(order) {
  return isOutsideSellerDelivery(order) && String(order.paymentMethod || "").toLowerCase() === "cash";
}

function foodPaymentConfirmed(order) {
  const status = order.paymentStatus || "pending";
  return status === "seller_confirmed" || status === "paid";
}

function deliveryCashSettled(order) {
  const charge = Number(order.deliveryCharge || 0);
  if (charge <= 0) return true;
  return Boolean(order.deliveryCashConfirmedAt);
}

/**
 * Mirrors the current order completion and payment rules.
 * The order machine has no delivered or failed status. Seller completion is
 * the only way an order becomes completed. Ready, accepted, and pending do
 * not qualify. Cancelled and rejected orders never qualify. Payload fields
 * are not read.
 */
function qualifyOrder(order) {
  if (!order) return { qualified: false, reason: "ENTITY_NOT_FOUND" };
  if (order.status === "cancelled" || order.status === "rejected") {
    return { qualified: false, reason: "ORDER_NOT_QUALIFIED" };
  }
  if (order.status !== "completed") return { qualified: false, reason: "ORDER_NOT_COMPLETED" };

  const method = String(order.paymentMethod || "").toLowerCase();
  const paymentStatus = order.paymentStatus || "pending";
  const provider = order.paymentProvider || null;

  if (isUpiFoodCashDeliverySplit(order)) {
    if (!foodPaymentConfirmed(order) || !deliveryCashSettled(order)) {
      return { qualified: false, reason: "PAYMENT_NOT_CONFIRMED" };
    }
    return { qualified: true, reason: null };
  }
  if (isCodOutsideSellerDelivery(order)) {
    return paymentStatus === "paid"
      ? { qualified: true, reason: null }
      : { qualified: false, reason: "PAYMENT_NOT_CONFIRMED" };
  }
  if (provider === "cashfree") {
    return paymentStatus === "paid"
      ? { qualified: true, reason: null }
      : { qualified: false, reason: "PAYMENT_NOT_CONFIRMED" };
  }
  if (method === "cash") {
    return paymentStatus === "paid"
      ? { qualified: true, reason: null }
      : { qualified: false, reason: "PAYMENT_NOT_CONFIRMED" };
  }
  if (method === "upi" && (provider == null || provider === "direct_upi")) {
    return foodPaymentConfirmed(order)
      ? { qualified: true, reason: null }
      : { qualified: false, reason: "PAYMENT_NOT_CONFIRMED" };
  }
  return { qualified: false, reason: "PAYMENT_NOT_CONFIRMED" };
}

module.exports = {
  deliveryCashSettled,
  isCodOutsideSellerDelivery,
  isUpiFoodCashDeliverySplit,
  qualifyOrder,
};
