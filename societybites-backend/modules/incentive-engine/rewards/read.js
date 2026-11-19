const { httpError } = require("../lib/httpError");
const { presentEvent } = require("../events/process");
const { effectiveFlags } = require("../configuration/flags");
const { cents, money } = require("./ledger");
const { presentReward } = require("./issue");

const ISSUED_STATUSES = Object.freeze(["ISSUED", "PARTIALLY_REDEEMED", "REDEEMED"]);
const REWARD_TYPES = Object.freeze(["FIXED_COUPON", "PERCENTAGE_COUPON", "PROMOTIONAL_CREDIT", "POINTS"]);

function typeKey(versionId, slot) {
  return `${versionId}:${slot}`;
}

function pageLimit(value, fallback = 20) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) return fallback;
  return Math.min(parsed, 50);
}

function requireUserId(userId) {
  if (!userId) throw httpError(401, "User is required");
  return String(userId);
}

async function loadRewardTypes(client, rows) {
  const pairs = [];
  const seen = new Set();
  for (const row of rows) {
    if (!row || !row.campaignVersionId || !row.rewardSlot) continue;
    const key = typeKey(row.campaignVersionId, row.rewardSlot);
    if (seen.has(key)) continue;
    seen.add(key);
    pairs.push({ versionId: row.campaignVersionId, slot: row.rewardSlot });
  }
  const types = new Map();
  if (!pairs.length || !client.incentiveRewardDefinition || typeof client.incentiveRewardDefinition.findMany !== "function") {
    return types;
  }
  const definitions = await client.incentiveRewardDefinition.findMany({
    where: { OR: pairs },
    select: { versionId: true, slot: true, rewardType: true },
  });
  for (const definition of definitions) {
    types.set(typeKey(definition.versionId, definition.slot), definition.rewardType || null);
  }
  return types;
}

async function presentRewards(client, rows) {
  const types = await loadRewardTypes(client, rows);
  return rows.map((row) => presentReward(row, types.get(typeKey(row.campaignVersionId, row.rewardSlot)) || null));
}

function sumAmounts(rows) {
  let total = 0;
  for (const row of rows) {
    const value = cents(row.amount);
    if (value == null) continue;
    total += value;
  }
  return money(total);
}

async function balancesFor(client, userId) {
  const rewards = await client.incentiveReward.findMany({
    where: { recipientUserId: userId },
    select: { id: true, campaignVersionId: true, rewardSlot: true },
  });
  const types = await loadRewardTypes(client, rewards);
  const creditIds = [];
  const pointIds = [];
  for (const reward of rewards) {
    const type = types.get(typeKey(reward.campaignVersionId, reward.rewardSlot));
    if (type === "PROMOTIONAL_CREDIT") creditIds.push(reward.id);
    if (type === "POINTS") pointIds.push(reward.id);
  }
  async function total(ids) {
    if (!ids.length) return "0.00";
    const entries = await client.incentiveLedgerEntry.findMany({
      where: { rewardId: { in: ids } },
      select: { amount: true },
    });
    return sumAmounts(entries);
  }
  const [promotionalCredit, points] = await Promise.all([total(creditIds), total(pointIds)]);
  return { promotionalCredit, points };
}

async function listOwnRewards(client, userId, query = {}) {
  const caller = requireUserId(userId);
  const where = { recipientUserId: caller };
  if (query.status) where.status = String(query.status);
  const rows = await client.incentiveReward.findMany({
    where,
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  let rewards = await presentRewards(client, rows);
  if (query.rewardType && REWARD_TYPES.includes(String(query.rewardType))) {
    rewards = rewards.filter((row) => row.rewardType === String(query.rewardType));
  }
  const balances = await balancesFor(client, caller);
  return { rewards, balances };
}

async function listOwnHistory(client, userId, query = {}) {
  const caller = requireUserId(userId);
  const rewards = await client.incentiveReward.findMany({
    where: { recipientUserId: caller },
    select: { id: true, campaignVersionId: true, rewardSlot: true },
  });
  const types = await loadRewardTypes(client, rewards);
  let owned = rewards;
  if (query.rewardType && REWARD_TYPES.includes(String(query.rewardType))) {
    owned = rewards.filter((row) => types.get(typeKey(row.campaignVersionId, row.rewardSlot)) === String(query.rewardType));
  }
  const ids = owned.map((row) => row.id);
  if (!ids.length) return { entries: [], nextCursor: null };
  const limit = pageLimit(query.limit);
  const where = { rewardId: { in: ids } };
  if (query.entryType) where.entryType = String(query.entryType);
  const found = await client.incentiveLedgerEntry.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: limit + 1,
    ...(query.cursor ? { cursor: { id: String(query.cursor) }, skip: 1 } : {}),
  });
  const page = found.slice(0, limit);
  const typeByReward = new Map(owned.map((row) => [row.id, types.get(typeKey(row.campaignVersionId, row.rewardSlot)) || null]));
  return {
    entries: page.map((entry) => ({
      id: entry.id,
      rewardId: entry.rewardId,
      recipientUserId: caller,
      rewardType: typeByReward.get(entry.rewardId) || null,
      entryType: entry.entryType,
      amount: entry.amount == null ? null : String(entry.amount),
      reason: entry.reason || null,
      idempotencyKey: entry.idempotencyKey,
      createdAt: entry.createdAt,
    })),
    nextCursor: found.length > limit ? page[page.length - 1].id : null,
  };
}

function emptyTypeCounts() {
  return { fixedCoupons: 0, percentageCoupons: 0, promotionalCredits: 0, points: 0, untyped: 0 };
}

async function overview(client) {
  const issuedWhere = { status: { in: ISSUED_STATUSES } };
  const [campaigns, active, referrals, qualified, issued, awaitingApproval, groups, events] = await Promise.all([
    client.incentiveCampaign.count(),
    client.incentiveCampaign.count({ where: { status: "ACTIVE" } }),
    client.incentiveReferral.count(),
    client.incentiveReferral.count({ where: { status: "QUALIFIED" } }),
    client.incentiveReward.count({ where: issuedWhere }),
    client.incentiveReward.count({ where: { status: "PENDING_APPROVAL" } }),
    client.incentiveReward.groupBy({
      by: ["campaignVersionId", "rewardSlot"],
      where: issuedWhere,
      _count: { _all: true },
    }),
    client.incentiveEvent.findMany({ orderBy: { occurredAt: "desc" }, take: 8 }),
  ]);
  const counts = emptyTypeCounts();
  const types = await loadRewardTypes(client, groups);
  for (const group of groups) {
    const count = group._count && group._count._all ? group._count._all : 0;
    const type = types.get(typeKey(group.campaignVersionId, group.rewardSlot));
    if (type === "FIXED_COUPON") counts.fixedCoupons += count;
    else if (type === "PERCENTAGE_COUPON") counts.percentageCoupons += count;
    else if (type === "PROMOTIONAL_CREDIT") counts.promotionalCredits += count;
    else if (type === "POINTS") counts.points += count;
    else counts.untyped += count;
  }
  return {
    campaigns: { total: campaigns, active },
    referrals: { total: referrals, qualified },
    rewards: { issued, awaitingApproval, ...counts },
    recentEvents: events.map(presentEvent),
  };
}

async function listLedger(client, query = {}) {
  const limit = pageLimit(query.limit);
  const where = {};
  if (query.entryType) where.entryType = String(query.entryType);
  if (query.rewardId) where.rewardId = String(query.rewardId);
  if (query.userId) where.reward = { recipientUserId: String(query.userId) };
  if (query.rewardType && REWARD_TYPES.includes(String(query.rewardType))) {
    const definitions = await client.incentiveRewardDefinition.findMany({
      where: { rewardType: String(query.rewardType) },
      select: { versionId: true, slot: true },
    });
    if (!definitions.length) return { entries: [], nextCursor: null };
    const typed = definitions.map((definition) => ({
      reward: { campaignVersionId: definition.versionId, rewardSlot: definition.slot },
    }));
    where.AND = [...(where.AND || []), { OR: typed }];
  }
  const found = await client.incentiveLedgerEntry.findMany({
    where,
    include: {
      reward: {
        select: { recipientUserId: true, campaignVersionId: true, rewardSlot: true },
      },
    },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: limit + 1,
    ...(query.cursor ? { cursor: { id: String(query.cursor) }, skip: 1 } : {}),
  });
  const page = found.slice(0, limit);
  const types = await loadRewardTypes(client, page.map((entry) => entry.reward).filter(Boolean));
  return {
    entries: page.map((entry) => ({
      id: entry.id,
      rewardId: entry.rewardId,
      recipientUserId: entry.reward ? entry.reward.recipientUserId : null,
      rewardSlot: entry.reward ? entry.reward.rewardSlot : null,
      rewardType: entry.reward ? types.get(typeKey(entry.reward.campaignVersionId, entry.reward.rewardSlot)) || null : null,
      entryType: entry.entryType,
      amount: entry.amount == null ? null : String(entry.amount),
      currency: entry.currency || "INR",
      reason: entry.reason || null,
      idempotencyKey: entry.idempotencyKey,
      createdAt: entry.createdAt,
    })),
    nextCursor: found.length > limit ? page[page.length - 1].id : null,
  };
}

async function reconcileBudget(client, campaignId) {
  if (!campaignId) throw httpError(400, "Campaign is required", "CAMPAIGN_REQUIRED");
  const campaign = await client.incentiveCampaign.findUnique({ where: { id: String(campaignId) } });
  if (!campaign) throw httpError(404, "Campaign not found", "CAMPAIGN_NOT_FOUND");
  const versions = await client.incentiveCampaignVersion.findMany({
    where: { campaignId: campaign.id },
    select: { id: true },
  });
  const ids = versions.map((row) => row.id);
  const budgets = ids.length ? await client.incentiveBudget.findMany({ where: { versionId: { in: ids } } }) : [];
  const rewards = ids.length
    ? await client.incentiveReward.findMany({
      where: { campaignVersionId: { in: ids } },
      select: { id: true, status: true },
    })
    : [];
  const rewardIds = rewards.map((row) => row.id);
  const entries = rewardIds.length
    ? await client.incentiveLedgerEntry.findMany({
      where: { rewardId: { in: rewardIds } },
      select: { entryType: true, amount: true },
    })
    : [];
  const configured = budgets.reduce((sum, row) => sum + (cents(row.amountCap) || 0), 0);
  const reserved = budgets.reduce((sum, row) => sum + (cents(row.issuedAmount) || 0), 0);
  const byStatus = {};
  for (const reward of rewards) byStatus[reward.status] = (byStatus[reward.status] || 0) + 1;
  const ledger = { ISSUE: 0, REDEEM: 0, EXPIRE: 0, OTHER: 0 };
  for (const entry of entries) {
    const key = Object.prototype.hasOwnProperty.call(ledger, entry.entryType) && entry.entryType !== "OTHER"
      ? entry.entryType
      : "OTHER";
    ledger[key] += cents(entry.amount) || 0;
  }
  return {
    campaignId: campaign.id,
    configured: money(configured),
    reserved: money(reserved),
    remaining: money(configured - reserved),
    rewards: byStatus,
    ledger: {
      issued: money(ledger.ISSUE),
      redeemed: money(ledger.REDEEM),
      expired: money(ledger.EXPIRE),
      other: money(ledger.OTHER),
    },
    reversedRewards: byStatus.REVERSED || 0,
    note: "Reserved budget is IncentiveBudget.issuedAmount. Rejection releases it. Reversal entries are not posted. Historical rows are not rewritten.",
  };
}

const SELLER_OFFER_CATEGORIES = new Set(["SELLER_ACQUISITION", "LISTING"]);

function publicOffer(campaign, version) {
  const snapshot = version && version.snapshot && typeof version.snapshot === "object" ? version.snapshot : {};
  const rewards = Array.isArray(snapshot.rewards) ? snapshot.rewards : [];
  const audiences = Array.isArray(snapshot.audiences) ? snapshot.audiences : [];
  const triggers = Array.isArray(snapshot.triggers) ? snapshot.triggers : [];
  return {
    id: campaign.id,
    name: campaign.name,
    description: campaign.description || null,
    category: campaign.category,
    endsAt: campaign.endsAt || null,
    rewards: rewards.map((row) => ({
      slot: row.slot,
      recipientRole: row.recipientRole,
      rewardType: row.rewardType,
      amount: row.amount == null ? null : String(row.amount),
      expiryDays: row.expiryDays == null ? null : row.expiryDays,
    })),
    audienceKinds: audiences.map((row) => row && row.kind).filter(Boolean),
    triggerEvents: triggers.map((row) => row && row.eventType).filter(Boolean),
    qualifiesWhen: "An order qualifies only after the seller marks it completed and the payment is confirmed. Pending, accepted, and ready orders do not qualify.",
  };
}

async function listVisibleOffers(client, { role } = {}) {
  const empty = (reason) => ({ offers: [], reason });
  let flags;
  try {
    const rows = await client.incentiveSetting.findMany({ select: { key: true, value: true } });
    flags = effectiveFlags(rows);
  } catch (error) {
    return empty("ENGINE_OFF");
  }
  if (!flags.master) return empty("ENGINE_OFF");
  let campaigns;
  try {
    campaigns = await client.incentiveCampaign.findMany({ where: { status: "ACTIVE" } });
  } catch (error) {
    return empty("ENGINE_OFF");
  }
  const seller = role === "seller";
  const offers = [];
  for (const campaign of campaigns) {
    const sellerOffer = SELLER_OFFER_CATEGORIES.has(campaign.category);
    if (seller !== sellerOffer) continue;
    if (!campaign.currentVersionId) continue;
    const version = await client.incentiveCampaignVersion.findUnique({ where: { id: campaign.currentVersionId } });
    if (!version || !version.publishedAt) continue;
    offers.push(publicOffer(campaign, version));
  }
  return { offers, reason: offers.length ? null : "NONE_ACTIVE" };
}

module.exports = {
  ISSUED_STATUSES,
  listLedger,
  listOwnHistory,
  listOwnRewards,
  overview,
  presentRewards,
  reconcileBudget,
  listVisibleOffers,
};
