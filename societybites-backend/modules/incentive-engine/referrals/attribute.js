const { httpError } = require("../lib/httpError");
const { qualifyOrder } = require("../events/qualifyOrder");
const { effectiveFlags } = require("../configuration/flags");
const { leaderboard: loadLeaderboard } = require("../analytics/query");
const { qualificationNote } = require("../analytics/report");

const KINDS = new Set(["BUYER_ACQUISITION", "SELLER_ACQUISITION"]);
const ISSUABLE = new Set(["ACTIVE", "SCHEDULED"]);
const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;

function text(value, label, max) {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed) throw httpError(400, `${label} is required`);
  if (trimmed.length > max) throw httpError(400, `${label} must be at most ${max} characters`);
  return trimmed;
}

function windowEnd(snapshot, policy, attributedAt) {
  const days = policy.qualificationWindowDays;
  const fromWindow = days == null ? null : new Date(attributedAt.getTime() + days * DAY_MS);
  const pinnedEnd = snapshot.endsAt ? new Date(snapshot.endsAt) : null;
  if (fromWindow && pinnedEnd) return fromWindow < pinnedEnd ? fromWindow : pinnedEnd;
  return fromWindow || pinnedEnd;
}

function presentReferral(row, names) {
  const referrerName = names && names[row.referrerUserId];
  return {
    id: row.id,
    acquisitionKind: row.acquisitionKind,
    status: row.status,
    attributedAt: new Date(row.attributedAt).toISOString(),
    windowEndsAt: row.windowEndsAt ? new Date(row.windowEndsAt).toISOString() : null,
    sellerActivated: Boolean(row.sellerEnabledAt),
    listingPublished: Boolean(row.listingId),
    orderQualified: Boolean(row.qualifyingOrderId),
    referrerName: referrerName || "Member",
    qualificationNote: qualificationNote(row),
  };
}

function raise(status, message, code, campaignId) {
  const error = httpError(status, message, code);
  if (campaignId) error.campaignId = campaignId;
  throw error;
}

function assertKindFlags(flags, kind) {
  if (!flags || flags.master !== true || flags.referral !== true) {
    throw httpError(403, "Referral attribution is off", "REFERRAL_DISABLED");
  }
  if (kind === "BUYER_ACQUISITION" && flags.buyerReferral !== true) {
    throw httpError(403, "Buyer referral attribution is off", "REFERRAL_DISABLED");
  }
  if (kind === "SELLER_ACQUISITION" && flags.sellerReferral !== true) {
    throw httpError(403, "Seller referral attribution is off", "REFERRAL_DISABLED");
  }
}

function assertAudience(audience, kind) {
  if (audience === "ANY") return;
  if (audience === "BUYER" && kind === "BUYER_ACQUISITION") return;
  if (audience === "SELLER" && kind === "SELLER_ACQUISITION") return;
  throw httpError(400, "This code does not match the referral kind", "ACQUISITION_MISMATCH");
}

function accountTooOld(createdAt, hours, now) {
  const created = new Date(createdAt);
  if (Number.isNaN(created.getTime())) return true;
  return now.getTime() - created.getTime() > hours * HOUR_MS;
}

async function claimReferral(db, { user, body, now = new Date() }) {
  const kind = typeof body?.acquisitionKind === "string" ? body.acquisitionKind.trim() : "";
  if (!KINDS.has(kind)) throw httpError(400, "Referral kind is invalid", "ACQUISITION_INVALID");
  const flags = db.readFlags ? await db.readFlags() : null;
  assertKindFlags(flags, kind);
  const referredUserId = user && user.id;
  if (!referredUserId) throw httpError(401, "User is required");
  const codeValue = text(body && body.code, "Referral code", 16);
  const code = await db.findCode(codeValue);
  const linkedCampaignId = code && code.campaignId ? code.campaignId : null;
  if (!code || code.active === false) raise(404, "Referral code is not valid", "CODE_INVALID", linkedCampaignId);
  if (code.expiresAt && new Date(code.expiresAt).getTime() <= now.getTime()) {
    raise(409, "Referral code has expired", "CODE_EXPIRED", linkedCampaignId);
  }
  try {
    assertAudience(code.audience, kind);
  } catch (error) {
    if (linkedCampaignId) error.campaignId = linkedCampaignId;
    throw error;
  }
  if (code.userId === referredUserId) raise(409, "A user cannot refer themselves", "SELF_REFERRAL", linkedCampaignId);

  const existing = await db.findReferral(referredUserId, kind);
  if (existing) {
    if (existing.codeId === code.id && existing.referrerUserId === code.userId) {
      return { created: false, referral: existing };
    }
    raise(409, "A referrer is already recorded", "REFERRER_ALREADY_SET", linkedCampaignId);
  }

  const referrer = await db.findUser(code.userId);
  if (!referrer || referrer.suspended) raise(409, "Referrer is not available", "REFERRER_UNAVAILABLE", linkedCampaignId);
  if ((code.audience === "SELLER" || code.audience === "ANY") && referrer.role !== "seller" && referrer.role !== "super_admin") {
    raise(409, "Referrer cannot sponsor this referral", "REFERRER_ROLE", linkedCampaignId);
  }
  const reverse = await db.findReverse(code.userId, referredUserId);
  if (reverse) raise(409, "These users already refer each other", "CIRCULAR_REFERRAL", linkedCampaignId);

  if (!code.campaignVersionId) raise(409, "Referral code is not pinned to a campaign version", "CAMPAIGN_VERSION_UNPUBLISHED", linkedCampaignId);
  const version = await db.findVersion(code.campaignVersionId);
  const campaign = code.campaignId ? await db.findCampaign(code.campaignId) : null;
  const campaignLink = campaign && campaign.id ? campaign.id : linkedCampaignId;
  if (!version || !version.publishedAt || !campaign || version.campaignId !== campaign.id) {
    raise(409, "Referral code is not pinned to a published campaign version", "CAMPAIGN_VERSION_UNPUBLISHED", campaignLink);
  }
  if (!ISSUABLE.has(campaign.status)) raise(409, "This campaign is not accepting referrals", "CAMPAIGN_NOT_ISSUABLE", campaign.id);
  if (campaign.category === "BUYER_ACQUISITION" && kind !== "BUYER_ACQUISITION") {
    raise(409, "This campaign does not accept that referral kind", "CAMPAIGN_KIND_MISMATCH", campaign.id);
  }
  if (campaign.category === "SELLER_ACQUISITION" && kind !== "SELLER_ACQUISITION") {
    raise(409, "This campaign does not accept that referral kind", "CAMPAIGN_KIND_MISMATCH", campaign.id);
  }
  const snapshot = version.snapshot || {};
  const policy = snapshot.referralPolicy || {};
  if (kind === "BUYER_ACQUISITION") {
    const hours = policy.buyer && policy.buyer.maxAccountAgeHours;
    if (!Number.isInteger(hours)) raise(400, "Buyer referral eligibility window is required", "ATTRIBUTION_WINDOW_REQUIRED", campaign.id);
    if (accountTooOld(user.createdAt, hours, now)) raise(409, "This account cannot claim a buyer referral", "ACCOUNT_NOT_ELIGIBLE", campaign.id);
    if (await db.buyerHasQualifyingOrder(referredUserId)) raise(409, "Qualifying activity already exists", "PRIOR_ACTIVITY", campaign.id);
  } else {
    const hours = policy.seller && policy.seller.maxAccountAgeHours;
    if (hours != null && accountTooOld(user.createdAt, hours, now)) {
      raise(409, "This account cannot claim a seller referral", "ACCOUNT_NOT_ELIGIBLE", campaign.id);
    }
    const sellerBlock = await db.sellerBlocked(referredUserId);
    if (sellerBlock) raise(409, "Seller activity already exists", sellerBlock, campaign.id);
  }

  const windowEndsAt = windowEnd(snapshot, policy, now);
  if (!windowEndsAt || windowEndsAt <= now) raise(409, "Referral window is closed", "WINDOW_CLOSED", campaign.id);

  if (policy.maxAttributionsPerReferrer != null) {
    await db.lockCodes(code.userId, code.campaignVersionId);
    const used = await db.countAttributions(code.userId, code.campaignVersionId, kind);
    if (used >= policy.maxAttributionsPerReferrer) raise(409, "Referral limit has been reached", "REFERRAL_LIMIT", campaign.id);
  }

  try {
    const created = await db.insertReferral({
      codeId: code.id,
      campaignId: campaign.id,
      campaignVersionId: code.campaignVersionId,
      referrerUserId: code.userId,
      referredUserId,
      acquisitionKind: kind,
      channel: body && body.channel ? text(body.channel, "Channel", 40) : null,
      attributedAt: now,
      windowEndsAt,
      status: "ATTRIBUTED",
    });
    await db.audit({
      actorId: referredUserId,
      action: "REFERRAL_ATTRIBUTED",
      campaignId: campaign.id,
      before: null,
      after: { referralId: created.id, referrerUserId: code.userId, acquisitionKind: kind },
    });
    return { created: true, referral: created };
  } catch (error) {
    if (!error || error.code !== "P2002") throw error;
    const raced = await db.findReferral(referredUserId, kind);
    if (raced && raced.codeId === code.id && raced.referrerUserId === code.userId) return { created: false, referral: raced };
    raise(409, "A referrer is already recorded", "REFERRER_ALREADY_SET", campaign.id);
  }
}

function createPrismaReferralDb(prisma) {
  return {
    async claim(input) {
      try {
        return await prisma.$transaction((tx) => claimReferral(txDb(tx), input));
      } catch (error) {
        if (error && error.statusCode && error.code) {
          try {
            const kind = input && input.body && typeof input.body.acquisitionKind === "string"
              ? input.body.acquisitionKind.slice(0, 40)
              : null;
            await prisma.incentiveAuditLog.create({
              data: {
                actorId: input && input.user && input.user.id ? input.user.id : "system",
                action: "REFERRAL_CLAIM_REJECTED",
                campaignId: error.campaignId || null,
                before: null,
                after: { reason: error.code, acquisitionKind: kind },
              },
            });
          } catch (auditError) {
            console.error("[incentive-referrals] rejection was not recorded");
          }
        }
        throw error;
      }
    },
    leaderboard(input) {
      return loadLeaderboard(prisma, input || {});
    },
    listForUser(userId) {
      return prisma.incentiveReferral.findMany({
        where: { OR: [{ referrerUserId: userId }, { referredUserId: userId }] },
        orderBy: { attributedAt: "desc" },
      });
    },
    names(ids) {
      return prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } });
    },
  };
}

function txDb(tx) {
  return {
    async readFlags() {
      const rows = await tx.incentiveSetting.findMany({ select: { key: true, value: true } });
      return effectiveFlags(rows);
    },
    findCode: (code) => tx.incentiveReferralCode.findUnique({ where: { code } }),
    findUser: (id) => tx.user.findUnique({ where: { id } }),
    findCampaign: (id) => tx.incentiveCampaign.findUnique({ where: { id } }),
    findVersion: (id) => tx.incentiveCampaignVersion.findUnique({ where: { id } }),
    findReferral: (referredUserId, acquisitionKind) => tx.incentiveReferral.findUnique({
      where: { referredUserId_acquisitionKind: { referredUserId, acquisitionKind } },
    }),
    findReverse: (referrerUserId, referredUserId) => tx.incentiveReferral.findFirst({
      where: { referrerUserId: referredUserId, referredUserId: referrerUserId },
    }),
    async buyerHasQualifyingOrder(userId) {
      const orders = tx["order"];
      const rows = await orders.findMany({
        where: { buyerId: userId },
        include: { items: { include: { listing: { select: { sellerId: true, societyId: true } } } } },
        take: 100,
      });
      return rows.some((order) => qualifyOrder(order).qualified);
    },
    async sellerBlocked(userId) {
      const terms = await tx.sellerTermsAcceptance.findFirst({ where: { userId } });
      if (terms) return "PRIOR_SELLER_ACTIVITY";
      const listing = await tx.listing.findFirst({ where: { sellerId: userId, NOT: { status: "draft" } } });
      if (listing) return "PRIOR_LISTING";
      const orders = tx["order"];
      const rows = await orders.findMany({
        where: { items: { some: { listing: { sellerId: userId } } } },
        include: { items: { include: { listing: { select: { sellerId: true, societyId: true } } } } },
        take: 100,
      });
      if (rows.some((order) => qualifyOrder(order).qualified)) return "PRIOR_ACTIVITY";
      return null;
    },
    lockCodes(referrerUserId, campaignVersionId) {
      return tx.$queryRaw`
        SELECT id FROM "IncentiveReferralCode"
        WHERE "userId" = ${referrerUserId} AND "campaignVersionId" = ${campaignVersionId}
        ORDER BY id
        FOR UPDATE
      `;
    },
    countAttributions(referrerUserId, campaignVersionId, acquisitionKind) {
      return tx.incentiveReferral.count({ where: { referrerUserId, campaignVersionId, acquisitionKind } });
    },
    insertReferral: (data) => tx.incentiveReferral.create({ data }),
    audit: (data) => tx.incentiveAuditLog.create({ data }),
  };
}

module.exports = {
  claimReferral,
  createPrismaReferralDb,
  presentReferral,
};
