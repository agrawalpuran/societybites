const prisma = require("../prisma");
const { DIRECT_UPI, normalizePaymentProvider, httpError } = require("./providers");

const PAYMENT_PROVIDER_KEY = "payment_provider";

async function getPaymentProvider() {
  const row = await prisma.appSetting.findUnique({
    where: { key: PAYMENT_PROVIDER_KEY },
  });
  if (!row) return DIRECT_UPI;
  return normalizePaymentProvider(row.value);
}

async function setPaymentProvider(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (normalized !== "direct_upi" && normalized !== "cashfree") {
    throw httpError(
      400,
      "paymentProvider must be direct_upi or cashfree"
    );
  }
  await prisma.appSetting.upsert({
    where: { key: PAYMENT_PROVIDER_KEY },
    update: { value: normalized },
    create: { key: PAYMENT_PROVIDER_KEY, value: normalized },
  });
  return normalized;
}

module.exports = {
  PAYMENT_PROVIDER_KEY,
  getPaymentProvider,
  setPaymentProvider,
};
