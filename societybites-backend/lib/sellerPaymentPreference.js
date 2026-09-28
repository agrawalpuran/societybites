function isSellerRole(role) {
  return role === "seller" || role === "super_admin";
}

const PAYMENT_PREFERENCES = Object.freeze({
  UPI_ONLY: "UPI_ONLY",
  UPI_AND_COD: "UPI_AND_COD",
  COD_IN_SOCIETY_UPI_OUTSIDE: "COD_IN_SOCIETY_UPI_OUTSIDE",
});

const DEFAULT_PAYMENT_PREFERENCE = PAYMENT_PREFERENCES.COD_IN_SOCIETY_UPI_OUTSIDE;
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
    raw === "COD_IN_SOCIETY_UPI_OUTSIDE" ||
    raw === "COD_IN_SOCIETY" ||
    raw === "COD_SOCIETY" ||
    raw === "IN_SOCIETY_COD"
  ) {
    return PAYMENT_PREFERENCES.COD_IN_SOCIETY_UPI_OUTSIDE;
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
    throw httpError(
      400,
      "paymentPreference must be UPI_ONLY, UPI_AND_COD, or COD_IN_SOCIETY_UPI_OUTSIDE"
    );
  }
  const raw = String(value).trim().toUpperCase();
  if (!ALLOWED_PAYMENT_PREFERENCES.includes(raw)) {
    throw httpError(
      400,
      "paymentPreference must be UPI_ONLY, UPI_AND_COD, or COD_IN_SOCIETY_UPI_OUTSIDE"
    );
  }
  return raw;
}

function allowsCod(preference, { sameSociety = true } = {}) {
  const normalized = normalizePaymentPreference(preference);
  if (normalized === PAYMENT_PREFERENCES.UPI_ONLY) return false;
  if (normalized === PAYMENT_PREFERENCES.COD_IN_SOCIETY_UPI_OUTSIDE) {
    return sameSociety !== false;
  }
  return normalized === PAYMENT_PREFERENCES.UPI_AND_COD;
}

function allowsUpi(preference, { sameSociety = true } = {}) {
  const normalized = normalizePaymentPreference(preference);
  if (normalized === PAYMENT_PREFERENCES.COD_IN_SOCIETY_UPI_OUTSIDE) {
    return sameSociety === false;
  }
  return true;
}

function assertSellerPaymentPreferenceUpdate({ requested, role }) {
  if (!isSellerRole(role)) {
    throw httpError(400, "Only sellers can change payment methods");
  }
  return parsePaymentPreference(requested);
}

function assertPaymentMethodAllowed({
  preference,
  paymentMethod,
  sameSociety = true,
}) {
  const method = String(paymentMethod || "upi").trim().toLowerCase();
  if (method !== "upi" && method !== "cash") {
    throw httpError(400, "paymentMethod must be 'upi' or 'cash'");
  }
  if (method === "upi" && !allowsUpi(preference, { sameSociety })) {
    throw httpError(
      400,
      "This seller accepts cash on delivery from buyers in the same society"
    );
  }
  if (method === "cash" && !allowsCod(preference, { sameSociety })) {
    const inSocietyOnly =
      normalizePaymentPreference(preference) ===
      PAYMENT_PREFERENCES.COD_IN_SOCIETY_UPI_OUTSIDE;
    throw httpError(
      400,
      inSocietyOnly
        ? "This seller accepts cash only from buyers in the same society"
        : "This seller accepts UPI only"
    );
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
  allowsUpi,
  assertSellerPaymentPreferenceUpdate,
  assertPaymentMethodAllowed,
  isUpiPaymentConfirmed,
  upiBlocksPreparation,
  serializePaymentPreference,
};
