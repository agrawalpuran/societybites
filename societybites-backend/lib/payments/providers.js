const DIRECT_UPI = "direct_upi";
const CASHFREE = "cashfree";
const ALLOWED = new Set([DIRECT_UPI, CASHFREE]);

function normalizePaymentProvider(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return ALLOWED.has(normalized) ? normalized : DIRECT_UPI;
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

module.exports = {
  DIRECT_UPI,
  CASHFREE,
  ALLOWED,
  normalizePaymentProvider,
  httpError,
};
