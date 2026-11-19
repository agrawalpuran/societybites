const crypto = require("crypto");
const { httpError } = require("../lib/httpError");
const { inspectReferralPolicy, REFERRAL_CATEGORIES } = require("../campaign/config");

const AUDIENCES = new Set(["BUYER", "SELLER", "ANY"]);
const ISSUABLE = new Set(["ACTIVE", "SCHEDULED"]);
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 16;
const CODE_ATTEMPTS = 5;
const DAY_MS = 24 * 60 * 60 * 1000;

function text(value, label, max) {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed) throw httpError(400, `${label} is required`);
  if (trimmed.length > max) throw httpError(400, `${label} must be at most ${max} characters`);
  return trimmed;
}

function listedFields(value) {
  if (Array.isArray(value)) return value.map((field) => String(field));
  if (typeof value !== "string" || !value) return [];
  const wrapped = value.match(/fields:\s*\(([^)]*)\)/);
  const source = wrapped ? wrapped[1] : value;
  return source.split(",").map((field) => field.replace(/[`\s"]/g, "")).filter(Boolean);
}

function uniqueKind(error) {
  if (!error || error.code !== "P2002") return null;
  const meta = error.meta || {};
  const described = [meta.constraint, meta.target, error.message]
    .map((part) => (typeof part === "string" ? part : JSON.stringify(part || "")))
    .join(" ");
  const fields = listedFields(meta.target).length > 0 ? listedFields(meta.target) : listedFields(error.message);
  if (
    (fields.includes("userId") && fields.includes("audience") && fields.includes("scopeKey")) ||
    described.includes("userId_audience_scopeKey")
  ) {
    return "owner";
  }
  if ((fields.length === 1 && fields[0] === "code") || described.includes("code_key")) return "code";
  return null;
}

function generateReferralCode() {
  const bytes = crypto.randomBytes(CODE_LENGTH);
  let code = "";
  for (let index = 0; index < CODE_LENGTH; index += 1) {
    code += CODE_ALPHABET[bytes[index] % CODE_ALPHABET.length];
  }
  return code;
}

function referralLinkBase(env = process.env) {
  const value = env.REFERRAL_LINK_BASE_URL;
  if (typeof value !== "string" || value.length === 0 || value.trim() !== value) return null;
  let parsed;
  try {
    parsed = new URL(value);
  } catch (error) {
    return null;
  }
  if (parsed.protocol !== "https:") return null;
  if (parsed.username || parsed.password) return null;
  if (parsed.search || parsed.hash) return null;
  if (parsed.pathname !== "/" && parsed.pathname !== "") return null;
  return parsed.origin;
}

function presentCode(row, env = process.env) {
  const expiresAt = row.expiresAt ? new Date(row.expiresAt).toISOString() : null;
  const base = referralLinkBase(env);
  return {
    code: row.code,
    audience: row.audience,
    expiresAt,
    campaignId: row.campaignId || null,
    campaignVersionId: row.campaignVersionId || null,
    active: row.active !== false,
    path: `/r/${row.code}`,
    url: base ? `${base}/r/${row.code}` : null,
  };
}

function assertFlags(flags, audience) {
  if (!flags || flags.master !== true || flags.referral !== true) {
    throw httpError(403, "Referral codes are off", "REFERRAL_DISABLED");
  }
  if (audience === "BUYER" && flags.buyerReferral !== true) {
    throw httpError(403, "Buyer referral codes are off", "REFERRAL_DISABLED");
  }
  if (audience === "SELLER" && flags.sellerReferral !== true) {
    throw httpError(403, "Seller referral codes are off", "REFERRAL_DISABLED");
  }
  if (audience === "ANY" && (flags.buyerReferral !== true || flags.sellerReferral !== true)) {
    throw httpError(403, "Referral codes for both audiences are off", "REFERRAL_DISABLED");
  }
}

function assertRole(user, audience) {
  if (audience === "BUYER") return;
  const role = user && user.role;
  if (role === "seller" || role === "super_admin") return;
  throw httpError(403, "Seller access is required for this referral code", "SELLER_REQUIRED");
}

function assertIssuable(status) {
  if (ISSUABLE.has(status)) return;
  const codes = {
    DRAFT: "CAMPAIGN_NOT_ACTIVE",
    PAUSED: "CAMPAIGN_PAUSED",
    COMPLETED: "CAMPAIGN_NOT_ACTIVE",
    EXPIRED: "CAMPAIGN_EXPIRED",
    TERMINATED: "CAMPAIGN_TERMINATED",
  };
  throw httpError(409, "This campaign cannot issue referral codes", codes[status] || "CAMPAIGN_NOT_ACTIVE");
}

function expiryFromSnapshot(snapshot, now) {
  const inspected = inspectReferralPolicy(snapshot.referralPolicy, {
    category: snapshot.category,
    endsAt: snapshot.endsAt,
  });
  if (inspected.failures.length > 0) {
    const failure = inspected.failures[0];
    throw httpError(400, failure.message, failure.code);
  }
  const days = inspected.policy.codeExpiresInDays;
  const fromLifetime = days == null ? null : new Date(now.getTime() + days * DAY_MS);
  const pinnedEnd = snapshot.endsAt ? new Date(snapshot.endsAt) : null;
  if (fromLifetime && pinnedEnd) return fromLifetime < pinnedEnd ? fromLifetime : pinnedEnd;
  return fromLifetime || pinnedEnd;
}

async function insertOrReuse(repository, row, generate) {
  let lastCollision = null;
  for (let attempt = 0; attempt < CODE_ATTEMPTS; attempt += 1) {
    const code = generate();
    try {
      const created = await repository.insertCode({ ...row, code });
      return { created: true, code: created };
    } catch (error) {
      const kind = uniqueKind(error);
      if (kind === "owner") {
        const existing = await repository.findCodeByOwner(row.userId, row.audience, row.scopeKey);
        if (existing) return { created: false, code: existing };
      } else if (kind === "code") {
        lastCollision = error;
        continue;
      }
      throw error;
    }
  }
  if (lastCollision) throw httpError(409, "Referral code could not be created", "CODE_COLLISION");
  throw httpError(409, "Referral code could not be created", "CODE_COLLISION");
}

async function createReferralCode(repository, { user, body, now = new Date(), generateCode = generateReferralCode, env = process.env }) {
  const audience = typeof body?.audience === "string" ? body.audience.trim() : "";
  if (!AUDIENCES.has(audience)) throw httpError(400, "Referral audience is invalid", "AUDIENCE_INVALID");
  const flags = await repository.readFlags();
  assertFlags(flags, audience);
  assertRole(user, audience);
  const userId = user && user.id;
  if (!userId) throw httpError(401, "User is required");
  const campaignId = text(body && body.campaignId, "Campaign", 80);
  const scopeKey = campaignId;
  const existing = await repository.findCodeByOwner(userId, audience, scopeKey);
  if (existing) {
    if (existing.active === false) {
      throw httpError(409, "This referral code is inactive", "CODE_INACTIVE");
    }
    return { created: false, code: presentCode(existing, env) };
  }

  const campaign = await repository.findCampaign(campaignId);
  if (!campaign) throw httpError(404, "Campaign not found");
  if (!REFERRAL_CATEGORIES.has(campaign.category)) {
    throw httpError(409, "This campaign does not issue referral codes", "CAMPAIGN_NOT_REFERRAL");
  }
  assertIssuable(campaign.status);
  if (!campaign.currentVersionId) {
    throw httpError(409, "Campaign version is not published", "CAMPAIGN_VERSION_UNPUBLISHED");
  }
  const version = await repository.findVersion(campaign.currentVersionId);
  if (!version || version.campaignId !== campaign.id || !version.publishedAt) {
    throw httpError(409, "Campaign version is not published", "CAMPAIGN_VERSION_UNPUBLISHED");
  }
  const snapshot = version.snapshot || {};
  const expiresAt = expiryFromSnapshot(
    { ...snapshot, category: snapshot.category || campaign.category },
    now
  );
  const result = await insertOrReuse(
    repository,
    {
      userId,
      audience,
      campaignId,
      scopeKey,
      active: true,
      expiresAt,
      campaignVersionId: version.id,
    },
    generateCode
  );
  return { created: result.created, code: presentCode(result.code, env) };
}

async function listReferralCodes(repository, { user, env = process.env }) {
  const flags = await repository.readFlags();
  if (!flags || flags.master !== true || flags.referral !== true) {
    throw httpError(403, "Referral codes are off", "REFERRAL_DISABLED");
  }
  const userId = user && user.id;
  if (!userId) throw httpError(401, "User is required");
  const rows = await repository.listCodes(userId);
  return { codes: rows.map((row) => presentCode(row, env)) };
}

function emptyPreview() {
  return { valid: false, audience: null, expiresAt: null };
}

async function previewReferralCode(repository, { code, now = new Date() }) {
  const flags = await repository.readFlags();
  if (!flags || flags.master !== true || flags.referral !== true) return emptyPreview();
  const normalized = typeof code === "string" ? code.trim() : "";
  if (!/^[0-9A-HJKMNP-TV-Z]{16}$/.test(normalized)) return emptyPreview();
  const row = await repository.findCodeByValue(normalized);
  if (!row || row.active === false) return emptyPreview();
  if (row.expiresAt && new Date(row.expiresAt).getTime() <= now.getTime()) return emptyPreview();
  return {
    valid: true,
    audience: row.audience,
    expiresAt: row.expiresAt ? new Date(row.expiresAt).toISOString() : null,
  };
}

module.exports = {
  createReferralCode,
  generateReferralCode,
  listReferralCodes,
  previewReferralCode,
  presentCode,
  referralLinkBase,
  uniqueKind,
};
