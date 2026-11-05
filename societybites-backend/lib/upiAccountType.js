const UPI_ACCOUNT_TYPES = Object.freeze({
  PERSONAL: "PERSONAL",
  MERCHANT: "MERCHANT",
});

const DEFAULT_UPI_ACCOUNT_TYPE = UPI_ACCOUNT_TYPES.PERSONAL;

function normalizeUpiAccountType(value, { fallback = DEFAULT_UPI_ACCOUNT_TYPE } = {}) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  const normalized = String(value).trim().toUpperCase();
  if (normalized === UPI_ACCOUNT_TYPES.MERCHANT || normalized === "BUSINESS") {
    return UPI_ACCOUNT_TYPES.MERCHANT;
  }
  if (normalized === UPI_ACCOUNT_TYPES.PERSONAL) {
    return UPI_ACCOUNT_TYPES.PERSONAL;
  }
  const err = new Error("upiAccountType must be PERSONAL or MERCHANT");
  err.statusCode = 400;
  throw err;
}

function isMerchantUpiAccountType(value) {
  try {
    return normalizeUpiAccountType(value) === UPI_ACCOUNT_TYPES.MERCHANT;
  } catch (_) {
    return false;
  }
}

module.exports = {
  UPI_ACCOUNT_TYPES,
  DEFAULT_UPI_ACCOUNT_TYPE,
  normalizeUpiAccountType,
  isMerchantUpiAccountType,
};
