const {
  SELLER,
  PROROUTING,
  normalizeDeliveryProvider,
  allowlistAllows,
  isProroutingEnvConfigured,
} = require("./deliverySetting");

function societyReadyForPartner(society) {
  if (!society) return false;
  const lat = Number(society.latitude);
  const lng = Number(society.longitude);
  const pincode = String(society.pincode || "").trim();
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
  if (!pincode) return false;
  return true;
}

function evaluatePartnerDelivery({
  provider,
  allowlist,
  buyerPhone,
  sellerPhone,
  orderType,
  isCrossSociety,
  fulfilmentMethod,
  paymentMethod,
  pickupSociety,
  dropSociety,
  env,
} = {}) {
  const reasons = [];
  if (normalizeDeliveryProvider(provider) !== PROROUTING) {
    reasons.push("provider_off");
  }
  if (!allowlistAllows(allowlist, buyerPhone, sellerPhone)) {
    reasons.push("allowlist");
  }
  if ((orderType || "regular") !== "regular") {
    reasons.push("order_type");
  }
  if (!isCrossSociety) {
    reasons.push("not_cross_society");
  }
  if (String(fulfilmentMethod || "").toLowerCase() !== "seller_delivery") {
    reasons.push("not_seller_delivery");
  }
  if (String(paymentMethod || "upi").toLowerCase() !== "upi") {
    reasons.push("not_upi");
  }
  if (!societyReadyForPartner(pickupSociety)) {
    reasons.push("pickup_society");
  }
  if (!societyReadyForPartner(dropSociety)) {
    reasons.push("drop_society");
  }
  if (!isProroutingEnvConfigured(env || process.env)) {
    reasons.push("env");
  }
  return {
    useProrouting: reasons.length === 0,
    reasons,
    provider: reasons.includes("provider_off") ? SELLER : PROROUTING,
  };
}

function isPartnerDeliveryOrder(order) {
  if (!order) return false;
  return (
    String(order.deliveryProvider || "").trim().toLowerCase() === PROROUTING
  );
}

module.exports = {
  societyReadyForPartner,
  evaluatePartnerDelivery,
  isPartnerDeliveryOrder,
};
