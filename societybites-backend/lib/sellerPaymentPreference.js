function isSellerRole(role) {
  return role === "seller" || role === "super_admin";
}

const PAYMENT_PREFERENCES = Object.freeze({
  UPI_ONLY: "UPI_ONLY",
  UPI_AND_COD: "UPI_AND_COD",
});

const DEFAULT_PAYMENT_PREFERENCE = PAYMENT_PREFERENCES.UPI_AND_COD;
const ALLOWED_PAYMENT_PREFERENCES = Object.freeze(Object.values(PAYMENT_PREFERENCES));

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function normalizePaymentPreference(value) {
  if (value == null || value === "") return DEFAULT_PAYMENT_PREFERENCE;
  const raw = String(value).trim().toUpperCase();
  if (raw === "UPI" || raw === "UPI-ONLY" || raw === "UPI_ONLY") {
    return PAYMENT_PREFERENCES.UPI_ONLY;
  }
  if (
    raw === "UPI_AND_COD" ||
    raw === "UPI+COD" ||
    raw === "BOTH" ||
    raw === "COD"
  ) {
    return PAYMENT_PREFERENCES.UPI_AND_COD;
  }
  if (ALLOWED_PAYMENT_PREFERENCES.includes(raw)) return raw;
  return DEFAULT_PAYMENT_PREFERENCE;
}

function parsePaymentPreference(value) {
  if (typeof value !== "string") {
    throw httpError(400, "paymentPreference must be UPI_ONLY or UPI_AND_COD");
  }
  const raw = String(value).trim().toUpperCase();
  if (!ALLOWED_PAYMENT_PREFERENCES.includes(raw)) {
    throw httpError(400, "paymentPreference must be UPI_ONLY or UPI_AND_COD");
  }
  return raw;
}

function allowsCod(preference) {
  return normalizePaymentPreference(preference) === PAYMENT_PREFERENCES.UPI_AND_COD;
}

function assertSellerPaymentPreferenceUpdate({ requested, role }) {
  if (!isSellerRole(role)) {
    throw httpError(400, "Only sellers can change payment methods");
  }
  return parsePaymentPreference(requested);
}

function assertPaymentMethodAllowed({ preference, paymentMethod }) {
  const method = String(paymentMethod || "upi").trim().toLowerCase();
  if (method !== "upi" && method !== "cash") {
    throw httpError(400, "paymentMethod must be 'upi' or 'cash'");
  }
  if (method === "cash" && !allowsCod(preference)) {
    throw httpError(400, "This seller accepts UPI only");
  }
  return method;
}

function isUpiPaymentConfirmed(order) {
  if (!order || String(order.paymentMethod || "upi").toLowerCase() !== "upi") {
    return true;
  }
  const status = order.paymentStatus || "pending";
  return status === "seller_confirmed" || status === "paid";
}

function upiBlocksPreparation(order) {
  if (!order || String(order.paymentMethod || "upi").toLowerCase() !== "upi") {
    return false;
  }
  return !isUpiPaymentConfirmed(order);
}

function serializePaymentPreference(user) {
  return normalizePaymentPreference(user && user.paymentPreference);
}

module.exports = {
  PAYMENT_PREFERENCES,
  DEFAULT_PAYMENT_PREFERENCE,
  ALLOWED_PAYMENT_PREFERENCES,
  normalizePaymentPreference,
  parsePaymentPreference,
  allowsCod,
  assertSellerPaymentPreferenceUpdate,
  assertPaymentMethodAllowed,
  isUpiPaymentConfirmed,
  upiBlocksPreparation,
  serializePaymentPreference,
};
