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

const DELIVERY_REACH = Object.freeze({
  IN_SOCIETY: "inSociety",
  NEARBY: "nearby",
  EXTENDED: "extended",
});

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

function parseDeliveryCharge(value, field = "deliveryCharge") {
  if (value === undefined || value === null || value === "") {
    return 0;
  }
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) {
    throw httpError(400, `${field} must be a number`);
  }
  if (n < 0) {
    throw httpError(400, `${field} must be >= 0`);
  }
  return n;
}

function numberOrZero(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function resolvedNearbyCharge(user) {
  const nearby = numberOrZero(user && user.deliveryChargeNearby);
  const legacy = numberOrZero(user && user.deliveryCharge);
  return nearby === 0 && legacy !== 0 ? legacy : nearby;
}

function resolvedExtendedCharge(user) {
  const nearby = resolvedNearbyCharge(user);
  const extended = numberOrZero(user && user.deliveryChargeExtended);
  return extended === 0 && nearby !== 0 && numberOrZero(user && user.deliveryChargeNearby) === 0
    ? nearby
    : extended;
}

function assertSellerFulfilmentUpdate({
  requestedMode,
  requestedCharge,
  requestedChargeInSociety,
  requestedChargeNearby,
  requestedChargeExtended,
  role,
} = {}) {
  if (!isSellerRole(role)) {
    throw httpError(400, "Only sellers can change fulfilment settings");
  }
  const mode = parseFulfilmentMode(requestedMode);
  const data = { fulfilmentMode: mode };

  const hasBandCharges =
    requestedChargeInSociety !== undefined ||
    requestedChargeNearby !== undefined ||
    requestedChargeExtended !== undefined;

  if (hasBandCharges) {
    if (requestedChargeInSociety !== undefined) {
      data.deliveryChargeInSociety = parseDeliveryCharge(
        requestedChargeInSociety,
        "deliveryChargeInSociety"
      );
    }
    if (requestedChargeNearby !== undefined) {
      data.deliveryChargeNearby = parseDeliveryCharge(
        requestedChargeNearby,
        "deliveryChargeNearby"
      );
    }
    if (requestedChargeExtended !== undefined) {
      data.deliveryChargeExtended = parseDeliveryCharge(
        requestedChargeExtended,
        "deliveryChargeExtended"
      );
    }
    if (data.deliveryChargeNearby !== undefined) {
      data.deliveryCharge = data.deliveryChargeNearby;
    }
  } else if (requestedCharge !== undefined) {
    const charge = parseDeliveryCharge(requestedCharge);
    data.deliveryCharge = charge;
    data.deliveryChargeNearby = charge;
    data.deliveryChargeExtended = charge;
  }

  return data;
}

function serializeFulfilment(user) {
  const mode = user && user.fulfilmentMode
    ? String(user.fulfilmentMode)
    : DEFAULT_FULFILMENT_MODE;
  const nearby = resolvedNearbyCharge(user);
  const inSociety = numberOrZero(user && user.deliveryChargeInSociety);
  const extended = resolvedExtendedCharge(user);
  if (!offersSellerDelivery(mode)) {
    return {
      mode,
      deliveryCharge: null,
      deliveryChargeInSociety: null,
      deliveryChargeNearby: null,
      deliveryChargeExtended: null,
    };
  }
  return {
    mode,
    deliveryCharge: nearby,
    deliveryChargeInSociety: inSociety,
    deliveryChargeNearby: nearby,
    deliveryChargeExtended: extended,
  };
}

function deliveryChargeForReach(seller, reachBand) {
  if (!offersSellerDelivery(seller && seller.fulfilmentMode)) return 0;
  if (reachBand === DELIVERY_REACH.IN_SOCIETY) {
    return numberOrZero(seller && seller.deliveryChargeInSociety);
  }
  if (reachBand === DELIVERY_REACH.EXTENDED) {
    return resolvedExtendedCharge(seller);
  }
  return resolvedNearbyCharge(seller);
}

module.exports = {
  FULFILMENT_MODES,
  DEFAULT_FULFILMENT_MODE,
  ALLOWED_FULFILMENT_MODES,
  DELIVERY_REACH,
  parseFulfilmentMode,
  parseDeliveryCharge,
  assertSellerFulfilmentUpdate,
  serializeFulfilment,
  offersSellerDelivery,
  deliveryChargeForReach,
};
