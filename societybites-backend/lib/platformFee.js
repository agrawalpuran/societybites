const prisma = require("./prisma");
const { canonicalCityKey } = require("./launchCity");
const { resolveAdminCityKey } = require("./adminCityDashboard");

const PLATFORM_FEE_KEY = "platform_fee";
const CITY_PLATFORM_FEES_KEY = "city_platform_fees";
const DEFAULT_PLATFORM_FEE = 0;
const CACHE_MS = 60_000;

let cachedFee = null;
let cachedAt = 0;
let cachedCityOverrides = null;
let cachedCityOverridesAt = 0;

function parseFee(value) {
  const n = parseFloat(value);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100) / 100;
}

function normalizeOverrides(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    const cityKey = String(key || "").trim().toLowerCase();
    if (!cityKey) continue;
    const fee = parseFee(value);
    if (fee === null) continue;
    out[cityKey] = fee;
  }
  return out;
}

async function getPlatformFee() {
  const now = Date.now();
  if (cachedFee !== null && now - cachedAt < CACHE_MS) {
    return cachedFee;
  }

  const row = await prisma.appSetting.findUnique({
    where: { key: PLATFORM_FEE_KEY },
  });

  if (!row) {
    cachedFee = DEFAULT_PLATFORM_FEE;
    cachedAt = now;
    return DEFAULT_PLATFORM_FEE;
  }

  const value = parseFee(row.value);
  if (value === null) {
    cachedFee = DEFAULT_PLATFORM_FEE;
    cachedAt = now;
    return DEFAULT_PLATFORM_FEE;
  }

  cachedFee = value;
  cachedAt = now;
  return value;
}

async function getCityPlatformFeeOverrides({ bypassCache = false } = {}) {
  const now = Date.now();
  if (
    !bypassCache &&
    cachedCityOverrides &&
    now - cachedCityOverridesAt < CACHE_MS
  ) {
    return cachedCityOverrides;
  }

  const row = await prisma.appSetting.findUnique({
    where: { key: CITY_PLATFORM_FEES_KEY },
  });
  let parsed = {};
  if (row && row.value) {
    try {
      parsed = normalizeOverrides(JSON.parse(row.value));
    } catch (_err) {
      parsed = {};
    }
  }
  cachedCityOverrides = parsed;
  cachedCityOverridesAt = now;
  return parsed;
}

function clearPlatformFeeCaches() {
  cachedFee = null;
  cachedAt = 0;
  cachedCityOverrides = null;
  cachedCityOverridesAt = 0;
}

async function resolvePlatformFee({ societyId = null, cityKey = null } = {}) {
  const globalFee = await getPlatformFee();
  let resolvedCityKey = cityKey ? String(cityKey).trim().toLowerCase() : "";
  if (!resolvedCityKey && societyId) {
    const society = await prisma.society.findUnique({
      where: { id: String(societyId) },
      select: { city: true },
    });
    resolvedCityKey = canonicalCityKey(society && society.city);
  }
  if (!resolvedCityKey) return globalFee;

  const overrides = await getCityPlatformFeeOverrides();
  if (!Object.prototype.hasOwnProperty.call(overrides, resolvedCityKey)) {
    return globalFee;
  }
  return overrides[resolvedCityKey];
}

async function setPlatformFee(fee) {
  const value = parseFee(fee);
  if (value === null) {
    const err = new Error("platformFee must be a number >= 0");
    err.statusCode = 400;
    throw err;
  }

  const row = await prisma.appSetting.upsert({
    where: { key: PLATFORM_FEE_KEY },
    update: { value: String(value) },
    create: { key: PLATFORM_FEE_KEY, value: String(value) },
  });

  cachedFee = parseFee(row.value) ?? DEFAULT_PLATFORM_FEE;
  cachedAt = Date.now();
  return cachedFee;
}

async function setCityPlatformFeeOverride(cityKey, fee, query = {}) {
  const resolvedKey = await resolveAdminCityKey({
    ...query,
    cityKey,
  });
  const value = parseFee(fee);
  if (value === null) {
    const err = new Error("platformFee must be a number >= 0");
    err.statusCode = 400;
    throw err;
  }

  const overrides = await getCityPlatformFeeOverrides({ bypassCache: true });
  overrides[resolvedKey] = value;

  await prisma.appSetting.upsert({
    where: { key: CITY_PLATFORM_FEES_KEY },
    update: { value: JSON.stringify(overrides) },
    create: { key: CITY_PLATFORM_FEES_KEY, value: JSON.stringify(overrides) },
  });
  clearPlatformFeeCaches();
  return { cityKey: resolvedKey, platformFee: value };
}

async function clearCityPlatformFeeOverride(cityKey, query = {}) {
  const resolvedKey = await resolveAdminCityKey({
    ...query,
    cityKey,
  });
  const overrides = await getCityPlatformFeeOverrides({ bypassCache: true });
  if (Object.prototype.hasOwnProperty.call(overrides, resolvedKey)) {
    delete overrides[resolvedKey];
    await prisma.appSetting.upsert({
      where: { key: CITY_PLATFORM_FEES_KEY },
      update: { value: JSON.stringify(overrides) },
      create: { key: CITY_PLATFORM_FEES_KEY, value: JSON.stringify(overrides) },
    });
  }
  clearPlatformFeeCaches();
  return resolvedKey;
}

async function getAdminPlatformFeePayload(cityKey = null) {
  const platformFeeGlobal = await getPlatformFee();
  const cityPlatformFeeOverrides = await getCityPlatformFeeOverrides();
  if (!cityKey) {
    return {
      platformFeeGlobal,
      platformFee: platformFeeGlobal,
      cityPlatformFeeOverride: null,
      usesGlobalPlatformFee: true,
      cityPlatformFeeOverrides,
    };
  }
  const key = String(cityKey).trim().toLowerCase();
  const hasOverride = Object.prototype.hasOwnProperty.call(
    cityPlatformFeeOverrides,
    key
  );
  const platformFee = hasOverride
    ? cityPlatformFeeOverrides[key]
    : platformFeeGlobal;
  return {
    platformFeeGlobal,
    platformFee,
    cityPlatformFeeOverride: hasOverride ? cityPlatformFeeOverrides[key] : null,
    usesGlobalPlatformFee: !hasOverride,
    cityPlatformFeeOverrides,
    cityKey: key,
  };
}

module.exports = {
  PLATFORM_FEE_KEY,
  CITY_PLATFORM_FEES_KEY,
  DEFAULT_PLATFORM_FEE,
  getPlatformFee,
  getCityPlatformFeeOverrides,
  resolvePlatformFee,
  setPlatformFee,
  setCityPlatformFeeOverride,
  clearCityPlatformFeeOverride,
  getAdminPlatformFeePayload,
  clearPlatformFeeCaches,
  normalizeOverrides,
};