const logger = require("../../../lib/logger");
const { httpError } = require("../lib/httpError");

/** IncentiveSetting keys. A missing row, or any value other than "true", is off. */
const FLAG_KEYS = Object.freeze({
  master: "master_enabled",
  issuance: "issuance_enabled",
  redemption: "redemption_enabled",
  referral: "referral_enabled",
  buyerReferral: "buyer_referral_enabled",
  sellerReferral: "seller_referral_enabled",
  promotional: "promotional_campaigns_enabled",
});

/** Switches a super admin may change. Issuance, redemption, and promotional stay without a writer. */
const WRITABLE_FLAG_KEYS = Object.freeze(["master", "referral", "buyerReferral", "sellerReferral"]);

const ALL_OFF = Object.freeze({
  master: false,
  issuance: false,
  redemption: false,
  referral: false,
  buyerReferral: false,
  sellerReferral: false,
  promotional: false,
});

function flagsOff() {
  return { ...ALL_OFF };
}

/**
 * Space, tab, newline, carriage return, form feed, and vertical tab.
 * This is the same set as PostgreSQL btrim(value, E' \t\n\r\f\v').
 * It does not use String.trim(), which also removes characters PostgreSQL leaves in place.
 */
function isEnabledValue(value) {
  if (typeof value !== "string") return false;
  return value.replace(/^[ \t\n\r\f\v]+/, "").replace(/[ \t\n\r\f\v]+$/, "") === "true";
}

/**
 * Effective switches. The master switch turns every other switch off.
 * Buyer and seller referral also require the referral switch.
 */
function effectiveFlags(rows) {
  const stored = Object.create(null);
  if (Array.isArray(rows)) {
    for (const row of rows) {
      if (row && typeof row.key === "string") stored[row.key] = row.value;
    }
  }
  const master = isEnabledValue(stored[FLAG_KEYS.master]);
  const referral = master && isEnabledValue(stored[FLAG_KEYS.referral]);
  return {
    master,
    issuance: master && isEnabledValue(stored[FLAG_KEYS.issuance]),
    redemption: master && isEnabledValue(stored[FLAG_KEYS.redemption]),
    referral,
    buyerReferral: referral && isEnabledValue(stored[FLAG_KEYS.buyerReferral]),
    sellerReferral: referral && isEnabledValue(stored[FLAG_KEYS.sellerReferral]),
    promotional: master && isEnabledValue(stored[FLAG_KEYS.promotional]),
  };
}

function storedFlags(rows) {
  const stored = Object.create(null);
  if (Array.isArray(rows)) {
    for (const row of rows) {
      if (row && typeof row.key === "string") stored[row.key] = row.value;
    }
  }
  return {
    master: isEnabledValue(stored[FLAG_KEYS.master]),
    issuance: isEnabledValue(stored[FLAG_KEYS.issuance]),
    redemption: isEnabledValue(stored[FLAG_KEYS.redemption]),
    referral: isEnabledValue(stored[FLAG_KEYS.referral]),
    buyerReferral: isEnabledValue(stored[FLAG_KEYS.buyerReferral]),
    sellerReferral: isEnabledValue(stored[FLAG_KEYS.sellerReferral]),
    promotional: isEnabledValue(stored[FLAG_KEYS.promotional]),
  };
}

async function readFlags({ loadRows } = {}) {
  if (typeof loadRows !== "function") return flagsOff();
  try {
    const rows = await loadRows();
    return effectiveFlags(rows);
  } catch (err) {
    logger.warn("incentive", "Flag read failed; engine stays off", {
      code: err && err.code ? String(err.code) : "FLAG_READ_FAILED",
    });
    return flagsOff();
  }
}

async function readFlagState({ loadRows } = {}) {
  if (typeof loadRows !== "function") return { ...flagsOff(), stored: flagsOff() };
  try {
    const rows = await loadRows();
    return { ...effectiveFlags(rows), stored: storedFlags(rows) };
  } catch (err) {
    logger.warn("incentive", "Flag read failed; engine stays off", {
      code: err && err.code ? String(err.code) : "FLAG_READ_FAILED",
    });
    return { ...flagsOff(), stored: flagsOff() };
  }
}

/**
 * Writes one referral-family switch. A missing row stays off until this stores "true".
 * "false" is off. Any other key is rejected and is not written.
 */
async function setWritableFlag(client, { actorId, key, enabled } = {}) {
  if (!actorId) throw httpError(401, "User is required");
  if (!WRITABLE_FLAG_KEYS.includes(key)) {
    throw httpError(400, "This switch cannot be changed here", "FLAG_NOT_WRITABLE");
  }
  if (typeof enabled !== "boolean") {
    throw httpError(400, "enabled must be true or false", "FLAG_VALUE_INVALID");
  }
  const storedKey = FLAG_KEYS[key];
  const value = enabled ? "true" : "false";
  return client.$transaction(async (tx) => {
    const existing = await tx.incentiveSetting.findUnique({ where: { key: storedKey } });
    const previous = existing ? existing.value : null;
    if (previous !== value) {
      await tx.incentiveSetting.upsert({
        where: { key: storedKey },
        create: { key: storedKey, value },
        update: { value },
      });
      if (tx.incentiveAuditLog && typeof tx.incentiveAuditLog.create === "function") {
        await tx.incentiveAuditLog.create({
          data: {
            actorId: String(actorId),
            action: "FLAG_CHANGED",
            before: { key: storedKey, value: previous },
            after: { key: storedKey, value },
          },
        });
      }
    }
    const rows = await tx.incentiveSetting.findMany({ select: { key: true, value: true } });
    return { ...effectiveFlags(rows), stored: storedFlags(rows) };
  });
}

module.exports = {
  ALL_OFF,
  FLAG_KEYS,
  WRITABLE_FLAG_KEYS,
  effectiveFlags,
  flagsOff,
  isEnabledValue,
  readFlagState,
  readFlags,
  setWritableFlag,
  storedFlags,
};
