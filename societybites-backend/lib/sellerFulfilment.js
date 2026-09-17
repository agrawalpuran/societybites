function isSellerRole(role) {
  return role === "seller" || role === "super_admin";
}

const FULFILMENT_MODES = Object.freeze({
  BUYER_PICKUP: "BUYER_PICKUP",
  SELLER_DELIVERY: "SELLER_DELIVERY",
  BOTH: "BOTH",
});

const DEFAULT_FULFILMENT_MODE = FULFILMENT_MODES.BUYER_PICKUP;
const ALLOWED_FULFILMENT_MODES = Object.freeze(Object.values(FULFILMENT_MODES));

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function offersSellerDelivery(mode) {
  return mode === FULFILMENT_MODES.SELLER_DELIVERY || mode === FULFILMENT_MODES.BOTH;
}

function parseFulfilmentMode(value) {
  if (typeof value !== "string") {
    throw httpError(400, "fulfilmentMode must be BUYER_PICKUP, SELLER_DELIVERY, or BOTH");
  }
  const mode = String(value).trim().toUpperCase();
  if (!ALLOWED_FULFILMENT_MODES.includes(mode)) {
    throw httpError(400, "fulfilmentMode must be BUYER_PICKUP, SELLER_DELIVERY, or BOTH");
  }
  return mode;
}

function parseDeliveryCharge(value) {
  if (value === undefined || value === null || value === "") {
    return 0;
  }
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) {
    throw httpError(400, "deliveryCharge must be a number");
  }
  if (n < 0) {
    throw httpError(400, "deliveryCharge must be >= 0");
  }
  return n;
}

function assertSellerFulfilmentUpdate({ requestedMode, requestedCharge, role }) {
  if (!isSellerRole(role)) {
    throw httpError(400, "Only sellers can change fulfilment settings");
  }
  const mode = parseFulfilmentMode(requestedMode);
  let deliveryCharge;
  if (requestedCharge === undefined) {
    deliveryCharge = undefined;
  } else {
    deliveryCharge = parseDeliveryCharge(requestedCharge);
  }
  return { fulfilmentMode: mode, deliveryCharge };
}

function serializeFulfilment(user) {
  const mode = user && user.fulfilmentMode
    ? String(user.fulfilmentMode)
    : DEFAULT_FULFILMENT_MODE;
  const rawCharge = user && user.deliveryCharge;
  const charge = Number.isFinite(Number(rawCharge)) ? Number(rawCharge) : 0;
  return {
    mode,
    deliveryCharge: offersSellerDelivery(mode) ? charge : null,
  };
}

module.exports = {
  FULFILMENT_MODES,
  DEFAULT_FULFILMENT_MODE,
  ALLOWED_FULFILMENT_MODES,
  parseFulfilmentMode,
  parseDeliveryCharge,
  assertSellerFulfilmentUpdate,
  serializeFulfilment,
  offersSellerDelivery,
};
