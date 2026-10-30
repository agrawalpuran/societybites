const { canonicalCityKey } = require("./launchCity");
const { serializeFulfilment, DEFAULT_FULFILMENT_MODE } = require("./sellerFulfilment");
const { serializePaymentPreference } = require("./sellerPaymentPreference");
const {
  serializeSellerFssai,
  canEnableSellingDespiteFssai,
} = require("./fssaiCompliance");
const { isFssaiSellingRequirementEnabled } = require("./fssaiRequirement");

const SELLING_REACH_LEVELS = Object.freeze({
  MY_SOCIETY: "MY_SOCIETY",
  BEYOND_SOCIETY: "BEYOND_SOCIETY",
  /** @deprecated migrated to BEYOND_SOCIETY + sellingReachRadiusKm */
  NEARBY: "NEARBY",
  /** @deprecated migrated to BEYOND_SOCIETY + sellingReachRadiusKm */
  EXTENDED: "EXTENDED",
});

const DEFAULT_SELLING_REACH_LEVEL = SELLING_REACH_LEVELS.MY_SOCIETY;
const DEFAULT_MAX_SELLER_RADIUS_KM = 10;

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

function sellsBeyondOwnSociety(level) {
  const normalized = normalizeSellingReachLevel(level);
  return (
    normalized === SELLING_REACH_LEVELS.BEYOND_SOCIETY ||
    normalized === SELLING_REACH_LEVELS.NEARBY ||
    normalized === SELLING_REACH_LEVELS.EXTENDED
  );
}

function parseRequestedSellingReachLevel(value) {
  if (typeof value !== "string") {
    throw httpError(
      400,
      "sellingReachLevel must be MY_SOCIETY or BEYOND_SOCIETY"
    );
  }
  const level = String(value).trim().toUpperCase();
  if (!ALLOWED_SELLING_REACH_LEVELS.includes(level)) {
    throw httpError(
      400,
      "sellingReachLevel must be MY_SOCIETY or BEYOND_SOCIETY"
    );
  }
  return level;
}

function maxSellerRadiusKmFromConfig(config) {
  if (config && Number.isFinite(Number(config.maxSellerRadiusKm))) {
    return Number(config.maxSellerRadiusKm);
  }
  return DEFAULT_MAX_SELLER_RADIUS_KM;
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
  const maxSellerRadiusKm = cityKey ? maxSellerRadiusKmFromConfig(config) : null;
  return {
    cityKey,
    nearbyRadiusKm: nearby,
    extendedRadiusKm: extended,
    maxSellerRadiusKm,
  };
}

/**
 * Applied radius for discovery when the seller sells beyond their society.
 * @returns {number|null}
 */
function resolveSellerAppliedRadiusKm(seller, cityReachConfig, societyCity) {
  const level = normalizeSellingReachLevel(seller && seller.sellingReachLevel);
  if (level === SELLING_REACH_LEVELS.MY_SOCIETY) return null;

  const stored = seller && seller.sellingReachRadiusKm;
  if (stored != null && Number.isFinite(Number(stored)) && Number(stored) > 0) {
    return Number(stored);
  }

  const reach = serializeSellingReach(societyCity, cityReachConfig);
  if (level === SELLING_REACH_LEVELS.NEARBY) return reach.nearbyRadiusKm;
  if (level === SELLING_REACH_LEVELS.EXTENDED) return reach.extendedRadiusKm;
  if (level === SELLING_REACH_LEVELS.BEYOND_SOCIETY) return null;
  return null;
}

function clampSellerRadiusKm(radiusKm, maxKm) {
  const max = Math.max(1, Math.round(maxKm));
  const rounded = Math.round(Number(radiusKm));
  if (!Number.isFinite(rounded)) {
    throw httpError(400, "sellingReachRadiusKm must be a whole number of km");
  }
  if (rounded < 1 || rounded > max) {
    throw httpError(
      400,
      `sellingReachRadiusKm must be between 1 and ${max} km for your city`
    );
  }
  return rounded;
}

/**
 * Validates seller reach settings (level + optional radius km).
 * @returns {{ sellingReachLevel: string, sellingReachRadiusKm: number|null }}
 */
async function assertSellerSellingReachSettings({
  requestedLevel,
  requestedRadiusKm,
  currentLevel,
  currentRadiusKm,
  role,
  societyCity,
  prismaClient,
}) {
  const levelRaw =
    requestedLevel !== undefined && requestedLevel !== null
      ? requestedLevel
      : currentLevel;
  const level = parseRequestedSellingReachLevel(String(levelRaw));

  if (level === SELLING_REACH_LEVELS.MY_SOCIETY) {
    return {
      sellingReachLevel: SELLING_REACH_LEVELS.MY_SOCIETY,
      sellingReachRadiusKm: null,
    };
  }

  if (!isSellerRole(role)) {
    throw httpError(400, "Only sellers can change selling reach");
  }

  const cityKey = canonicalCityKey(societyCity);
  let config = null;
  if (cityKey && prismaClient) {
    config = await prismaClient.cityReachConfig.findUnique({ where: { cityKey } });
  }
  const reach = serializeSellingReach(societyCity, config);
  const maxKm = reach.maxSellerRadiusKm ?? DEFAULT_MAX_SELLER_RADIUS_KM;

  if (level === SELLING_REACH_LEVELS.BEYOND_SOCIETY) {
    const radiusSource =
      requestedRadiusKm !== undefined && requestedRadiusKm !== null
        ? requestedRadiusKm
        : currentRadiusKm;
    if (radiusSource === undefined || radiusSource === null || radiusSource === "") {
      throw httpError(400, "sellingReachRadiusKm is required when selling beyond your society");
    }
    return {
      sellingReachLevel: SELLING_REACH_LEVELS.BEYOND_SOCIETY,
      sellingReachRadiusKm: clampSellerRadiusKm(radiusSource, maxKm),
    };
  }

  // Legacy NEARBY / EXTENDED (old clients)
  if (level === SELLING_REACH_LEVELS.NEARBY && reach.nearbyRadiusKm == null) {
    throw httpError(400, "Nearby selling is not available in your city yet.");
  }
  if (level === SELLING_REACH_LEVELS.EXTENDED && reach.extendedRadiusKm == null) {
    throw httpError(400, "Extended selling is not available in your city yet.");
  }
  const legacyKm =
    level === SELLING_REACH_LEVELS.NEARBY ? reach.nearbyRadiusKm : reach.extendedRadiusKm;
  return {
    sellingReachLevel: SELLING_REACH_LEVELS.BEYOND_SOCIETY,
    sellingReachRadiusKm: clampSellerRadiusKm(legacyKm, maxKm),
  };
}

/** @deprecated use assertSellerSellingReachSettings */
async function assertSellerSellingReachLevel({
  requested,
  role,
  societyCity,
  prismaClient,
}) {
  const result = await assertSellerSellingReachSettings({
    requestedLevel: requested,
    requestedRadiusKm: undefined,
    currentLevel: requested,
    currentRadiusKm: null,
    role,
    societyCity,
    prismaClient,
  });
  return result.sellingReachLevel;
}

function parseRadiusKm(value, field) {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) {
    throw httpError(400, `${field} must be a number`);
  }
  return n;
}

function hasRadiusValue(value) {
  return value !== undefined && value !== null && value !== "";
}

function validateCityReachRadii({ nearbyRadiusKm, extendedRadiusKm, maxSellerRadiusKm }) {
  let maxSeller = null;
  if (hasRadiusValue(maxSellerRadiusKm)) {
    maxSeller = parseRadiusKm(maxSellerRadiusKm, "maxSellerRadiusKm");
    if (!(maxSeller >= 1)) {
      throw httpError(400, "maxSellerRadiusKm must be at least 1");
    }
  }

  if (hasRadiusValue(nearbyRadiusKm) || hasRadiusValue(extendedRadiusKm)) {
    const nearby = parseRadiusKm(nearbyRadiusKm, "nearbyRadiusKm");
    const extended = parseRadiusKm(extendedRadiusKm, "extendedRadiusKm");
    if (!(nearby > 0)) {
      throw httpError(400, "nearbyRadiusKm must be greater than 0");
    }
    if (!(extended >= nearby)) {
      throw httpError(400, "extendedRadiusKm must be at least nearbyRadiusKm");
    }
    if (maxSeller == null) {
      maxSeller = extended;
    }
    return { nearbyRadiusKm: nearby, extendedRadiusKm: extended, maxSellerRadiusKm: maxSeller };
  }

  if (maxSeller == null) {
    throw httpError(400, "maxSellerRadiusKm is required");
  }
  return {
    nearbyRadiusKm: maxSeller,
    extendedRadiusKm: maxSeller,
    maxSellerRadiusKm: maxSeller,
  };
}

async function attachSellingReach(user, prismaClient) {
  const cityKey = canonicalCityKey(user && user.society && user.society.city);
  let config = null;
  if (cityKey) {
    config = await prismaClient.cityReachConfig.findUnique({ where: { cityKey } });
  }
  const sellerFssai = await prismaClient.sellerFssai.findUnique({
    where: { userId: user.id },
  });
  const assistance = await prismaClient.fssaiAssistanceRequest.findFirst({
    where: {
      userId: user.id,
      status: { in: ["NEW", "CONTACTED", "IN_PROGRESS"] },
    },
    orderBy: { requestedAt: "desc" },
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  const fssaiStatus = sellerFssai ? sellerFssai.status : "NOT_SUBMITTED";
  const fssaiPayload = {
    ...serializeSellerFssai(sellerFssai),
    requirementEnabled,
    assistanceRequested: Boolean(assistance),
    assistanceStatus: assistance ? assistance.status : null,
    canSellDespiteFssai: !requirementEnabled || fssaiStatus === "APPROVED",
    canEnableSellingDespiteFssai: canEnableSellingDespiteFssai(
      fssaiStatus,
      requirementEnabled,
      {
        assistanceRequested: Boolean(assistance),
        detailsDeferred: Boolean(sellerFssai && sellerFssai.detailsDeferred),
      }
    ),
  };
  return {
    ...user,
    sellingReachLevel: user.sellingReachLevel || DEFAULT_SELLING_REACH_LEVEL,
    sellingReachRadiusKm:
      user.sellingReachRadiusKm != null ? Number(user.sellingReachRadiusKm) : null,
    sellingReach: serializeSellingReach(user && user.society && user.society.city, config),
    fulfilmentMode: (user && user.fulfilmentMode) || DEFAULT_FULFILMENT_MODE,
    fulfilment: serializeFulfilment(user),
    paymentPreference: serializePaymentPreference(user),
    fssai: fssaiPayload,
  };
}

module.exports = {
  SELLING_REACH_LEVELS,
  DEFAULT_SELLING_REACH_LEVEL,
  DEFAULT_MAX_SELLER_RADIUS_KM,
  ALLOWED_SELLING_REACH_LEVELS,
  normalizeSellingReachLevel,
  parseRequestedSellingReachLevel,
  isSellerRole,
  sellsBeyondOwnSociety,
  resolveSellerAppliedRadiusKm,
  assertSellerSellingReachSettings,
  assertSellerSellingReachLevel,
  validateCityReachRadii,
  serializeSellingReach,
  maxSellerRadiusKmFromConfig,
  attachSellingReach,
};
