const prisma = require("./prisma");

const PLATFORM_FEE_KEY = "platform_fee";
const DEFAULT_PLATFORM_FEE = 0;

async function getPlatformFee() {
  const row = await prisma.appSetting.findUnique({
    where: { key: PLATFORM_FEE_KEY },
  });

  if (!row) return DEFAULT_PLATFORM_FEE;

  const value = parseFloat(row.value);
  if (!Number.isFinite(value) || value < 0) {
    return DEFAULT_PLATFORM_FEE;
  }

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

  return parseFloat(row.value);
}

module.exports = {
  PLATFORM_FEE_KEY,
  DEFAULT_PLATFORM_FEE,
  getPlatformFee,
  setPlatformFee,
};
