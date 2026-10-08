const prisma = require("./prisma");

const PLATFORM_FEE_KEY = "platform_fee";
const DEFAULT_PLATFORM_FEE = 0;
const CACHE_MS = 60_000;

let cachedFee = null;
let cachedAt = 0;

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

  const value = parseFloat(row.value);
  if (!Number.isFinite(value) || value < 0) {
    cachedFee = DEFAULT_PLATFORM_FEE;
    cachedAt = now;
    return DEFAULT_PLATFORM_FEE;
  }

  cachedFee = value;
  cachedAt = now;
  return value;
}

async function setPlatformFee(fee) {
  const value = parseFloat(fee);
  if (!Number.isFinite(value) || value < 0) {
    const err = new Error("platformFee must be a number >= 0");
    err.statusCode = 400;
    throw err;
  }

  const row = await prisma.appSetting.upsert({
    where: { key: PLATFORM_FEE_KEY },
    update: { value: String(value) },
    create: { key: PLATFORM_FEE_KEY, value: String(value) },
  });

  cachedFee = parseFloat(row.value);
  cachedAt = Date.now();
  return cachedFee;
}

module.exports = {
  PLATFORM_FEE_KEY,
  DEFAULT_PLATFORM_FEE,
  getPlatformFee,
  setPlatformFee,
};
