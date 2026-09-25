const { canonicalCityKey } = require("./launchCity");
const { serializeFulfilment, DEFAULT_FULFILMENT_MODE } = require("./sellerFulfilment");
const { serializePaymentPreference } = require("./sellerPaymentPreference");
const { serializeFssai } = require("./fssai");

const SELLING_REACH_LEVELS = Object.freeze({
  MY_SOCIETY: "MY_SOCIETY",
  NEARBY: "NEARBY",
  EXTENDED: "EXTENDED",
});

const DEFAULT_SELLING_REACH_LEVEL = SELLING_REACH_LEVELS.MY_SOCIETY;

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function normalizeSellingReachLevel(value) {
  if (value == null || value === "") return DEFAULT_SELLING_REACH_LEVEL;
  return String(value).trim().toUpperCase();
}

const ALLOWED_SELLING_REACH_LEVELS = Object.freeze(
  Object.values(SELLING_REACH_LEVELS)
);

function isSellerRole(role) {
  return role === "seller" || role === "super_admin";
}

function parseRequestedSellingReachLevel(value) {
  if (typeof value !== "string") {
    throw httpError(400, "sellingReachLevel must be MY_SOCIETY, NEARBY, or EXTENDED");
  }
  const level = String(value).trim().toUpperCase();
  if (!ALLOWED_SELLING_REACH_LEVELS.includes(level)) {
    throw httpError(400, "sellingReachLevel must be MY_SOCIETY, NEARBY, or EXTENDED");
  }
  return level;
}

/**
 * Sellers may store a reach level only. Radii come from CityReachConfig.
 * Client-supplied nearbyRadiusKm / extendedRadiusKm are ignored.
 */
async function assertSellerSellingReachLevel({
  requested,
  role,
  societyCity,
  prismaClient,
}) {
  const level = parseRequestedSellingReachLevel(requested);
  if (level === SELLING_REACH_LEVELS.MY_SOCIETY) return level;

  if (!isSellerRole(role)) {
    throw httpError(400, "Only sellers can change selling reach");
  }

  const cityKey = canonicalCityKey(societyCity);
  let config = null;
  if (cityKey && prismaClient) {
    config = await prismaClient.cityReachConfig.findUnique({ where: { cityKey } });
  }
  const reach = serializeSellingReach(societyCity, config);

  if (level === SELLING_REACH_LEVELS.NEARBY && reach.nearbyRadiusKm == null) {
    throw httpError(400, "Nearby selling is not available in your city yet.");
  }
  if (level === SELLING_REACH_LEVELS.EXTENDED && reach.extendedRadiusKm == null) {
    throw httpError(400, "Extended selling is not available in your city yet.");
  }
  return level;
}

function parseRadiusKm(value, field) {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) {
    throw httpError(400, `${field} must be a number`);
  }
  return n;
}

function validateCityReachRadii({ nearbyRadiusKm, extendedRadiusKm }) {
  const nearby = parseRadiusKm(nearbyRadiusKm, "nearbyRadiusKm");
  const extended = parseRadiusKm(extendedRadiusKm, "extendedRadiusKm");
  if (!(nearby > 0)) {
    throw httpError(400, "nearbyRadiusKm must be greater than 0");
  }
  if (!(extended > nearby)) {
    throw httpError(400, "extendedRadiusKm must be greater than nearbyRadiusKm");
  }
  return { nearbyRadiusKm: nearby, extendedRadiusKm: extended };
}

function serializeSellingReach(societyCity, config) {
  const cityKey = canonicalCityKey(societyCity) || null;
  const nearby =
    config && Number.isFinite(Number(config.nearbyRadiusKm))
      ? Number(config.nearbyRadiusKm)
      : null;
  const extended =
    config && Number.isFinite(Number(config.extendedRadiusKm))
      ? Number(config.extendedRadiusKm)
      : null;
  return {
    cityKey,
    nearbyRadiusKm: nearby,
    extendedRadiusKm: extended,
  };
}

async function attachSellingReach(user, prismaClient) {
  const cityKey = canonicalCityKey(user && user.society && user.society.city);
  let config = null;
  if (cityKey) {
    config = await prismaClient.cityReachConfig.findUnique({ where: { cityKey } });
  }
  return {
    ...user,
    sellingReachLevel: user.sellingReachLevel || DEFAULT_SELLING_REACH_LEVEL,
    sellingReach: serializeSellingReach(user && user.society && user.society.city, config),
    fulfilmentMode: (user && user.fulfilmentMode) || DEFAULT_FULFILMENT_MODE,
    fulfilment: serializeFulfilment(user),
    paymentPreference: serializePaymentPreference(user),
    fssai: serializeFssai(user),
  };
}

module.exports = {
  SELLING_REACH_LEVELS,
  DEFAULT_SELLING_REACH_LEVEL,
  ALLOWED_SELLING_REACH_LEVELS,
  normalizeSellingReachLevel,
  parseRequestedSellingReachLevel,
  isSellerRole,
  assertSellerSellingReachLevel,
  validateCityReachRadii,
  serializeSellingReach,
  attachSellingReach,
};
