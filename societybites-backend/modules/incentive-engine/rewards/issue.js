const crypto = require("crypto");
const { AsyncLocalStorage } = require("async_hooks");
const { createAssignedCoupon } = require("../../../lib/coupons");
const { cents, money, postEntry } = require("./ledger");

const budgetLockContext = new AsyncLocalStorage();

const COUPON_TYPES = new Set(["FIXED_COUPON", "PERCENTAGE_COUPON"]);
const LEDGER_TYPES = new Set(["PROMOTIONAL_CREDIT", "POINTS"]);
const ACTIVE_REWARD_STATUSES = new Set(["ISSUED", "PARTIALLY_REDEEMED", "REDEEMED"]);

function chargeFor(definition) {
  if (!definition || definition.rewardType === "POINTS") return 0;
  if (definition.rewardType === "PERCENTAGE_COUPON") return Number(definition.maxDiscount || 0);
  return Number(definition.amount || 0);
}

function rewardKey(versionId, eventId, userId, slot) {
  return `${versionId}:${eventId}:${userId}:${slot}`;
}

function couponCodeFor(idempotencyKey) {
  return `SB${crypto.createHash("sha256").update(String(idempotencyKey)).digest("hex").slice(0, 16).toUpperCase()}`;
}

function selectCampaigns(matches, campaigns) {
  const byId = new Map((campaigns || []).map((campaign) => [campaign.id, campaign]));
  const ranked = (matches || [])
    .filter((match) => match && match.passed === true)
    .map((match) => ({ match, campaign: byId.get(match.campaignId) }))
    .filter((row) => row.campaign && row.campaign.version && row.campaign.version.snapshot);
  ranked.sort((left, right) => Number(right.campaign.priority || 0) - Number(left.campaign.priority || 0));
  if (ranked.some((row) => row.campaign.stackingMode === "EXCLUSIVE" || row.campaign.stackingMode === "FIRST_MATCH")) {
    return ranked.slice(0, 1);
  }
  return ranked;
}

async function audit(tx, data) {
  if (!tx.incentiveAuditLog || typeof tx.incentiveAuditLog.create !== "function") return;
  await tx.incentiveAuditLog.create({ data });
}

async function withVersionLock(tx, versionId, work) {
  if (typeof tx.$queryRaw === "function") {
    await tx.$queryRaw`
      SELECT "id"
      FROM "IncentiveBudget"
      WHERE "versionId" = ${versionId}
      FOR UPDATE
    `;
    return work();
  }
  const bucket = tx.incentiveBudget;
  if (!bucket) return work();
  const frame = budgetLockContext.getStore();
  if (frame && frame.bucket === bucket && frame.versionId === versionId) return work();
  if (!bucket.queues) bucket.queues = new Map();
  if (!bucket.queues.has(versionId)) bucket.queues.set(versionId, Promise.resolve());
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const previous = bucket.queues.get(versionId);
  bucket.queues.set(versionId, previous.then(() => gate));
  await previous;
  try {
    return await budgetLockContext.run({ bucket, versionId }, work);
  } finally {
    release();
  }
}

async function readBudget(tx, versionId) {
  if (!tx.incentiveBudget) return null;
  if (typeof tx.incentiveBudget.findUnique === "function") {
    return tx.incentiveBudget.findUnique({ where: { versionId } });
  }
  const rows = tx.incentiveBudget.rows || [];
  return rows.find((row) => row.versionId === versionId) || null;
}

async function recipientFor(tx, definition, event, order) {
  const role = definition.recipientRole;
  if (role === "TRIGGER_USER") return { userId: event.userId || null, referralId: null };
  if (role === "BUYER") return { userId: (order && order.buyerId) || event.userId || null, referralId: null };
  if (role === "SELLER") {
    const listing = order && order.items && order.items[0] && order.items[0].listing;
    return { userId: (listing && listing.sellerId) || null, referralId: null };
  }
  if (!tx.incentiveReferral || typeof tx.incentiveReferral.findFirst !== "function") {
    return { userId: null, referralId: null };
  }
  const referral = event.type === "REFERRAL_ATTRIBUTED"
    ? await tx.incentiveReferral.findFirst({ where: { id: event.entityId } })
    : await tx.incentiveReferral.findFirst({
      where: { referredUserId: event.userId, status: { in: ["QUALIFIED", "PENDING_REVIEW"] } },
    });
  if (!referral) return { userId: null, referralId: null };
  return {
    userId: role === "REFERRER" ? referral.referrerUserId : referral.referredUserId,
    referralId: referral.id,
  };
}

async function issueOne(tx, input, definition) {
  const { event, campaign, now, order } = input;
  const versionId = campaign.version.id;
  const recipient = await recipientFor(tx, definition, event, order);
  if (!recipient.userId) return { skipped: { slot: definition.slot, reason: "RECIPIENT_UNAVAILABLE" } };
  const idempotencyKey = rewardKey(versionId, event.id, recipient.userId, definition.slot);
  return withVersionLock(tx, versionId, async () => {
    const existing = await tx.incentiveReward.findUnique({ where: { idempotencyKey } });
    if (existing) return { reward: existing, duplicate: true };
    const budget = await readBudget(tx, versionId);
    const charge = chargeFor(definition);
    const snapshotBudget = campaign.version.snapshot.budget || {};
    if (snapshotBudget.maxRewardAmount != null && cents(charge) > cents(snapshotBudget.maxRewardAmount)) {
      await audit(tx, {
        actorId: "system",
        action: "REWARD_BUDGET_EXHAUSTED",
        campaignId: campaign.id,
        incentiveEventId: event.id,
        after: { slot: definition.slot, reason: "REWARD_AMOUNT_EXCEEDS_CAP" },
      });
      return { skipped: { slot: definition.slot, reason: "REWARD_AMOUNT_EXCEEDS_CAP" } };
    }
    if (snapshotBudget.maxRewardCount != null) {
      const issuedCount = typeof tx.incentiveReward.count === "function"
        ? await tx.incentiveReward.count({
          where: { campaignVersionId: versionId, status: { not: "REJECTED" } },
        })
        : (tx.incentiveReward.rows || []).filter((row) => row.campaignVersionId === versionId && row.status !== "REJECTED").length;
      if (issuedCount >= Number(snapshotBudget.maxRewardCount)) {
        await audit(tx, {
          actorId: "system",
          action: "REWARD_BUDGET_EXHAUSTED",
          campaignId: campaign.id,
          incentiveEventId: event.id,
          after: { slot: definition.slot, reason: "REWARD_COUNT_EXHAUSTED" },
        });
        return { skipped: { slot: definition.slot, reason: "REWARD_COUNT_EXHAUSTED" } };
      }
    }
    if (!budget || cents(budget.issuedAmount) + cents(charge) > cents(budget.amountCap)) {
      await audit(tx, {
        actorId: "system",
        action: "REWARD_BUDGET_EXHAUSTED",
        campaignId: campaign.id,
        incentiveEventId: event.id,
        after: { slot: definition.slot, reason: "BUDGET_EXHAUSTED" },
      });
      return { skipped: { slot: definition.slot, reason: "BUDGET_EXHAUSTED" } };
    }
    const pending = definition.requireAdminApproval === true;
    const expiresAt = definition.expiryDays ? new Date(now.getTime() + definition.expiryDays * 24 * 60 * 60 * 1000) : null;
    let reward;
    try {
      reward = await tx.incentiveReward.create({
        data: {
          campaignVersionId: versionId,
          rewardSlot: definition.slot,
          recipientUserId: recipient.userId,
          sourceEventId: event.id,
          referralId: recipient.referralId,
          status: pending ? "PENDING_APPROVAL" : "ISSUED",
          amount: definition.amount,
          currency: "INR",
          expiresAt,
          idempotencyKey,
        },
      });
    } catch (error) {
      if (error && error.code === "P2002") {
        const saved = await tx.incentiveReward.findUnique({ where: { idempotencyKey } });
        if (saved) return { reward: saved, duplicate: true };
      }
      throw error;
    }
    if (!pending && COUPON_TYPES.has(definition.rewardType)) {
      const writer = input.couponWriter || createAssignedCoupon;
      const coupon = await writer(tx, {
        code: couponCodeFor(idempotencyKey),
        name: "SocietyEats reward",
        discountType: definition.rewardType === "PERCENTAGE_COUPON" ? "PERCENTAGE" : "FIXED",
        discountValue: Number(definition.amount),
        maximumDiscount: definition.rewardType === "PERCENTAGE_COUPON" ? Number(definition.maxDiscount) : undefined,
        minimumOrderValue: definition.minOrder == null ? 0 : Number(definition.minOrder),
        validFrom: now,
        validUntil: expiresAt || new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000),
        totalUsageLimit: definition.usageLimit || 1,
        usagePerBuyerLimit: 1,
        audienceType: "SELECTED_USERS",
        userIds: [recipient.userId],
        status: "ACTIVE",
      });
      reward = await tx.incentiveReward.update({
        where: { id: reward.id },
        data: { couponId: coupon.id },
      });
    }
    if (!pending && LEDGER_TYPES.has(definition.rewardType)) {
      await postEntry(tx, {
        rewardId: reward.id,
        entryType: "ISSUE",
        amount: definition.amount,
        actorId: "system",
        reason: definition.rewardType,
        idempotencyKey: `ISSUE:${idempotencyKey}`,
      });
    }
    if (charge > 0 && typeof tx.incentiveBudget.update === "function") {
      await tx.incentiveBudget.update({
        where: { id: budget.id },
        data: { issuedAmount: money(cents(budget.issuedAmount) + cents(charge)) },
      });
    } else if (charge > 0 && budget) {
      budget.issuedAmount = money(cents(budget.issuedAmount) + cents(charge));
    }
    await audit(tx, {
      actorId: "system",
      action: pending ? "REWARD_PENDING" : "REWARD_ISSUED",
      campaignId: campaign.id,
      incentiveEventId: event.id,
      after: {
        rewardId: reward.id,
        slot: definition.slot,
        status: reward.status,
        recipientUserId: reward.recipientUserId,
      },
    });
    return { reward };
  });
}

async function issueMatchedRewards(tx, input = {}) {
  if (!tx || !tx.incentiveReward || typeof tx.incentiveReward.create !== "function") {
    return { issued: [], pending: [], skipped: [], fresh: [] };
  }
  if (!input.flags || input.flags.issuance !== true) {
    return { issued: [], pending: [], skipped: [{ reason: "ISSUANCE_DISABLED" }], fresh: [] };
  }
  const result = { issued: [], pending: [], skipped: [], fresh: [] };
  for (const selected of selectCampaigns(input.matches, input.campaigns)) {
    const definitions = selected.campaign.version.snapshot.rewards || [];
    for (const definition of definitions) {
      if (!COUPON_TYPES.has(definition.rewardType) && !LEDGER_TYPES.has(definition.rewardType)) {
        result.skipped.push({ slot: definition.slot, reason: "REWARD_TYPE_UNSUPPORTED" });
        continue;
      }
      const saved = await issueOne(tx, { ...input, campaign: selected.campaign }, definition);
      if (saved.skipped) result.skipped.push(saved.skipped);
      else if (saved.reward.status === "PENDING_APPROVAL") {
        result.pending.push(saved.reward);
        if (!saved.duplicate) result.fresh.push(saved.reward);
      } else if (ACTIVE_REWARD_STATUSES.has(saved.reward.status)) {
        result.issued.push(saved.reward);
        if (!saved.duplicate) result.fresh.push(saved.reward);
      }
      else {
        result.skipped.push({
          slot: definition.slot,
          reason: "REWARD_CLOSED",
          status: saved.reward.status || null,
          rewardId: saved.reward.id,
        });
      }
    }
  }
  return result;
}

async function materialiseReward(tx, reward, definition, now, couponWriter) {
  if (COUPON_TYPES.has(definition.rewardType)) {
    const coupon = await (couponWriter || createAssignedCoupon)(tx, {
      code: couponCodeFor(reward.idempotencyKey),
      name: "SocietyEats reward",
      discountType: definition.rewardType === "PERCENTAGE_COUPON" ? "PERCENTAGE" : "FIXED",
      discountValue: Number(definition.amount),
      maximumDiscount: definition.rewardType === "PERCENTAGE_COUPON" ? Number(definition.maxDiscount) : undefined,
      minimumOrderValue: definition.minOrder == null ? 0 : Number(definition.minOrder),
      validFrom: now,
      validUntil: reward.expiresAt || new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000),
      totalUsageLimit: definition.usageLimit || 1,
      usagePerBuyerLimit: 1,
      audienceType: "SELECTED_USERS",
      userIds: [reward.recipientUserId],
      status: "ACTIVE",
    });
    return tx.incentiveReward.update({ where: { id: reward.id }, data: { couponId: coupon.id, status: "ISSUED" } });
  }
  await postEntry(tx, {
    rewardId: reward.id,
    entryType: "ISSUE",
    amount: reward.amount,
    actorId: "system",
    reason: definition.rewardType,
    idempotencyKey: `ISSUE:${reward.idempotencyKey}`,
  });
  return tx.incentiveReward.update({ where: { id: reward.id }, data: { status: "ISSUED" } });
}

function presentReward(row, rewardType = null) {
  if (!row) return null;
  return {
    id: row.id,
    campaignVersionId: row.campaignVersionId,
    rewardSlot: row.rewardSlot,
    recipientUserId: row.recipientUserId,
    sourceEventId: row.sourceEventId,
    referralId: row.referralId || null,
    couponId: row.couponId || null,
    rewardType: rewardType || null,
    status: row.status,
    amount: row.amount == null ? null : String(row.amount),
    currency: row.currency || "INR",
    expiresAt: row.expiresAt || null,
    idempotencyKey: row.idempotencyKey,
  };
}

module.exports = {
  chargeFor,
  couponCodeFor,
  issueMatchedRewards,
  materialiseReward,
  presentReward,
  readBudget,
  rewardKey,
  withBudgetLock: withVersionLock,
};
