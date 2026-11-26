function db() {
  return require("../prisma");
}

const DELIVERY_PROVIDER_KEY = "delivery_provider";
const DELIVERY_ALLOWLIST_KEY = "delivery_prorouting_allowlist";

const SELLER = "seller";
const PROROUTING = "prorouting";

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function normalizeDeliveryProvider(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (normalized === PROROUTING) return PROROUTING;
  return SELLER;
}

/** POC allowlist: any 10 digits, stored as +91XXXXXXXXXX. Login OTP still uses strict Indian mobiles. */
function normalizeAllowlistPhone(raw) {
  if (raw == null) return null;
  const digits = String(raw).replace(/\D/g, "");
  if (!digits) return null;
  let ten = digits;
  if (digits.length === 12 && digits.startsWith("91")) {
    ten = digits.slice(2);
  } else if (digits.length === 11 && digits.startsWith("0")) {
    ten = digits.slice(1);
  } else if (digits.length > 10) {
    ten = digits.slice(-10);
  }
  if (ten.length !== 10) return null;
  return `+91${ten}`;
}

/** Prorouting pickup/drop.phone: 10-digit string, no +91. */
function toProroutingPhone(raw) {
  const canonical = normalizeAllowlistPhone(raw);
  return canonical ? canonical.slice(3) : "";
}

function splitPhoneTokens(raw) {
  return String(raw || "")
    .split(/[\n\r,;]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseAllowlist(raw) {
  let list = raw;
  if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (!trimmed) return [];
    try {
      const parsed = JSON.parse(trimmed);
      list = Array.isArray(parsed) ? parsed : splitPhoneTokens(trimmed);
    } catch (_err) {
      list = splitPhoneTokens(trimmed);
    }
  }
  if (!Array.isArray(list)) return [];
  const out = [];
  const seen = new Set();
  for (const item of list) {
    const phone = normalizeAllowlistPhone(item);
    if (!phone || seen.has(phone)) continue;
    seen.add(phone);
    out.push(phone);
  }
  return out;
}

function allowlistAllows(allowlist, buyerPhone, sellerPhone) {
  if (!Array.isArray(allowlist) || allowlist.length === 0) return false;
  const buyer = normalizeAllowlistPhone(buyerPhone);
  const seller = normalizeAllowlistPhone(sellerPhone);
  if (!buyer || !seller) return false;
  const set = new Set(allowlist);
  return set.has(buyer) && set.has(seller);
}

function isProroutingEnvConfigured(env = process.env) {
  const key = String((env && env.PROROUTING_API_KEY) || "").trim();
  const base = String((env && env.PROROUTING_BASE_URL) || "").trim();
  return Boolean(key && base);
}

async function getDeliveryProvider() {
  try {
    const row = await db().appSetting.findUnique({
      where: { key: DELIVERY_PROVIDER_KEY },
    });
    if (!row) return SELLER;
    return normalizeDeliveryProvider(row.value);
  } catch (_err) {
    return SELLER;
  }
}

async function getDeliveryAllowlist() {
  try {
    const row = await db().appSetting.findUnique({
      where: { key: DELIVERY_ALLOWLIST_KEY },
    });
    if (!row) return [];
    return parseAllowlist(row.value);
  } catch (_err) {
    return [];
  }
}

async function setDeliveryProvider(value) {
  const normalized = String(value || "")
    .trim()
    .toLowerCase();
  if (normalized !== SELLER && normalized !== PROROUTING) {
    throw httpError(400, "deliveryProvider must be seller or prorouting");
  }
  await db().appSetting.upsert({
    where: { key: DELIVERY_PROVIDER_KEY },
    update: { value: normalized },
    create: { key: DELIVERY_PROVIDER_KEY, value: normalized },
  });
  return normalized;
}

async function setDeliveryAllowlist(value) {
  let tokens = value;
  if (typeof value === "string") {
    tokens = splitPhoneTokens(value);
    try {
      const parsed = JSON.parse(String(value).trim());
      if (Array.isArray(parsed)) tokens = parsed;
    } catch (_err) {
      // keep newline/comma tokens
    }
  }
  if (!Array.isArray(tokens)) {
    throw httpError(400, "deliveryAllowlist must be a list of phones");
  }
  const invalid = [];
  for (const item of tokens) {
    const text = String(item == null ? "" : item).trim();
    if (!text) continue;
    if (!normalizeAllowlistPhone(text)) invalid.push(text);
  }
  if (invalid.length) {
    throw httpError(
      400,
      "deliveryAllowlist entries must be 10-digit numbers"
    );
  }
  const phones = parseAllowlist(tokens);
  const stored = JSON.stringify(phones);
  await db().appSetting.upsert({
    where: { key: DELIVERY_ALLOWLIST_KEY },
    update: { value: stored },
    create: { key: DELIVERY_ALLOWLIST_KEY, value: stored },
  });
  return phones;
}

async function getDeliveryAdminPayload() {
  const [deliveryProvider, deliveryAllowlist] = await Promise.all([
    getDeliveryProvider(),
    getDeliveryAllowlist(),
  ]);
  return {
    deliveryProvider,
    deliveryAllowlist,
    deliveryAllowlistCount: deliveryAllowlist.length,
  };
}

module.exports = {
  DELIVERY_PROVIDER_KEY,
  DELIVERY_ALLOWLIST_KEY,
  SELLER,
  PROROUTING,
  normalizeDeliveryProvider,
  parseAllowlist,
  allowlistAllows,
  normalizeAllowlistPhone,
  toProroutingPhone,
  isProroutingEnvConfigured,
  getDeliveryProvider,
  getDeliveryAllowlist,
  setDeliveryProvider,
  setDeliveryAllowlist,
  getDeliveryAdminPayload,
};
