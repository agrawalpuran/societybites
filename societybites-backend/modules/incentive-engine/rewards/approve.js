const { isEnabledValue } = require("../configuration/flags");
const { httpError } = require("../lib/httpError");
const { balanceOf, cents, money, postEntry, withRewardLock } = require("./ledger");
const { chargeFor, materialiseReward, readBudget, withBudgetLock } = require("./issue");

async function audit(tx, data) {
  if (!tx.incentiveAuditLog || typeof tx.incentiveAuditLog.create !== "function") return;
  await tx.incentiveAuditLog.create({ data });
}

async function definitionFor(tx, reward) {
  if (!tx.incentiveCampaignVersion || typeof tx.incentiveCampaignVersion.findUnique !== "function") return null;
  const version = await tx.incentiveCampaignVersion.findUnique({ where: { id: reward.campaignVersionId } });
  const rewards = version && version.snapshot && version.snapshot.rewards;
  return (rewards || []).find((row) => row.slot === reward.rewardSlot) || null;
}

function issuanceDisabled() {
  return httpError(403, "Reward issuance is off", "ISSUANCE_DISABLED");
}

/**
 * Reads issuance_enabled inside the caller's transaction and locks that row
 * when it exists. The lock is held until the transaction commits, so a
 * concurrent change to that row waits until the coupon or ledger write finishes.
 * A missing row cannot be locked; the approval is refused and no reward is written.
 * A database error is also refused.
 */
async function assertIssuanceEnabled(tx) {
  let value;
  try {
    if (typeof tx.$queryRaw === "function") {
      const rows = await tx.$queryRaw`
        SELECT "value"
        FROM "IncentiveSetting"
        WHERE "key" = 'issuance_enabled'
        FOR UPDATE
      `;
      value = rows.length ? rows[0].value : null;
    } else if (tx.incentiveSetting && typeof tx.incentiveSetting.lock === "function") {
      value = await tx.incentiveSetting.lock();
    } else {
      value = null;
    }
  } catch (error) {
    if (error && error.code === "ISSUANCE_DISABLED") throw error;
    throw issuanceDisabled();
  }
  if (!isEnabledValue(value)) throw issuanceDisabled();
}

async function releaseLockedBudget(tx, reward, definition) {
  if (!definition) throw httpError(409, "Reward definition is missing", "REWARD_DEFINITION_MISSING");
  const charge = chargeFor(definition);
  if (!(charge > 0)) return;
  const budget = await readBudget(tx, reward.campaignVersionId);
  if (!budget) return;
  const next = Math.max(0, cents(budget.issuedAmount) - cents(charge));
  if (typeof tx.incentiveBudget.update === "function") {
    await tx.incentiveBudget.update({ where: { id: budget.id }, data: { issuedAmount: money(next) } });
  } else {
    budget.issuedAmount = money(next);
  }
}

async function approveReward(tx, { rewardId, actorId, now = new Date(), couponWriter } = {}) {
  if (!actorId) throw httpError(400, "Approval requires an actor", "ACTOR_REQUIRED");
  const reward = await tx.incentiveReward.findUnique({ where: { id: rewardId } });
  if (!reward) throw httpError(404, "Reward not found", "REWARD_NOT_FOUND");
  if (reward.status === "ISSUED" || reward.status === "PARTIALLY_REDEEMED" || reward.status === "REDEEMED") {
    return reward;
  }
  if (reward.status !== "PENDING_APPROVAL") {
    throw httpError(409, "This reward cannot be approved", "REWARD_NOT_PENDING");
  }
  await assertIssuanceEnabled(tx);
  return withRewardLock(tx, reward.id, async () => {
    const current = await tx.incentiveReward.findUnique({ where: { id: reward.id } });
    if (!current) throw httpError(404, "Reward not found", "REWARD_NOT_FOUND");
    if (current.status === "ISSUED" || current.status === "PARTIALLY_REDEEMED" || current.status === "REDEEMED") {
      return current;
    }
    if (current.status !== "PENDING_APPROVAL") {
      throw httpError(409, "This reward cannot be approved", "REWARD_NOT_PENDING");
    }
    const definition = await definitionFor(tx, current);
    if (!definition) throw httpError(409, "Reward definition is missing", "REWARD_DEFINITION_MISSING");
    const issued = await materialiseReward(tx, current, definition, now, couponWriter);
    await tx.incentiveApproval.create({
      data: { rewardId: current.id, action: "APPROVE", requestedBy: "system", decidedBy: actorId, decision: "APPROVED" },
    });
    await audit(tx, {
      actorId,
      action: "REWARD_APPROVED",
      after: { rewardId: current.id, status: "ISSUED" },
    });
    issued.recorded = true;
    return issued;
  });
}

async function rejectReward(tx, { rewardId, actorId, reason } = {}) {
  if (!actorId) throw httpError(400, "Rejection requires an actor", "ACTOR_REQUIRED");
  const reward = await tx.incentiveReward.findUnique({ where: { id: rewardId } });
  if (!reward) throw httpError(404, "Reward not found", "REWARD_NOT_FOUND");
  return withBudgetLock(tx, reward.campaignVersionId, async () => withRewardLock(tx, reward.id, async () => {
    const current = await tx.incentiveReward.findUnique({ where: { id: reward.id } });
    if (!current) throw httpError(404, "Reward not found", "REWARD_NOT_FOUND");
    if (current.status === "REJECTED") return current;
    if (current.status !== "PENDING_APPROVAL") {
      throw httpError(409, "This reward cannot be rejected", "REWARD_NOT_PENDING");
    }
    const definition = await definitionFor(tx, current);
    if (!definition) throw httpError(409, "Reward definition is missing", "REWARD_DEFINITION_MISSING");
    await releaseLockedBudget(tx, current, definition);
    const updated = await tx.incentiveReward.update({
      where: { id: current.id },
      data: { status: "REJECTED" },
    });
    await tx.incentiveApproval.create({
      data: {
        rewardId: current.id,
        action: "REJECT",
        requestedBy: "system",
        decidedBy: actorId,
        decision: "REJECTED",
        reason: reason ? String(reason).slice(0, 500) : null,
      },
    });
    await audit(tx, {
      actorId,
      action: "REWARD_REJECTED",
      after: { rewardId: current.id, status: "REJECTED" },
    });
    updated.recorded = true;
    return updated;
  }));
}

function creditStillOpen(reward, now) {
  if (!reward) return httpError(404, "Reward not found", "REWARD_NOT_FOUND");
  if (reward.couponId) return httpError(409, "Coupon rewards stay on the coupon path", "COUPON_REDEMPTION_UNCHANGED");
  if (reward.status !== "ISSUED" && reward.status !== "PARTIALLY_REDEEMED") {
    return httpError(409, "This credit cannot be redeemed", "REWARD_NOT_REDEEMABLE");
  }
  if (reward.expiresAt && new Date(reward.expiresAt).getTime() <= now.getTime()) {
    return httpError(409, "This credit has expired", "REWARD_EXPIRED");
  }
  return null;
}

async function campaignIdFor(tx, versionId) {
  if (!versionId || !tx.incentiveCampaignVersion || typeof tx.incentiveCampaignVersion.findUnique !== "function") return null;
  const version = await tx.incentiveCampaignVersion.findUnique({ where: { id: versionId } });
  return version && version.campaignId ? version.campaignId : null;
}

async function redemptionRows(tx, rewardId) {
  if (tx.incentiveRedemption && typeof tx.incentiveRedemption.findMany === "function") {
    return tx.incentiveRedemption.findMany({ where: { rewardId } });
  }
  if (tx.incentiveRedemption && typeof tx.incentiveRedemption.findFirst === "function") {
    const row = await tx.incentiveRedemption.findFirst({ where: { rewardId } });
    return row ? [row] : [];
  }
  return [];
}

async function assertRecipientOrder(tx, reward, orderId) {
  if (!orderId) return;
  if (!tx.order || typeof tx.order.findUnique !== "function") {
    throw httpError(404, "Order not found", "ORDER_NOT_FOUND");
  }
  const order = await tx.order.findUnique({
    where: { id: String(orderId) },
    select: { id: true, buyerId: true },
  });
  if (!order) throw httpError(404, "Order not found", "ORDER_NOT_FOUND");
  if (order.buyerId !== reward.recipientUserId) {
    throw httpError(409, "Credit can be redeemed only against the recipient's order", "REWARD_ORDER_MISMATCH");
  }
}

async function redeemReward(tx, { rewardId, amount, orderId, actorId, idempotencyKey, flags, now = new Date() } = {}) {
  if (!flags || flags.redemption !== true) {
    throw httpError(403, "Reward redemption is off", "REDEMPTION_DISABLED");
  }
  if (!actorId || !idempotencyKey) throw httpError(400, "Redemption requires an actor and an idempotency key", "ACTOR_REQUIRED");
  const reward = await tx.incentiveReward.findUnique({ where: { id: rewardId } });
  const refused = creditStillOpen(reward, now);
  if (refused) throw refused;
  await assertRecipientOrder(tx, reward, orderId);
  const requested = Math.abs(Number(amount)).toFixed(2);
  const saved = await withRewardLock(tx, reward.id, async () => {
    const current = await tx.incentiveReward.findUnique({ where: { id: reward.id } });
    const blocked = creditStillOpen(current, now);
    if (blocked) throw blocked;
    const key = `REDEEM:${current.id}:${idempotencyKey}`;
    const posted = await postEntry(tx, {
      rewardId: current.id,
      entryType: "REDEEM",
      amount: (-Number(requested)).toFixed(2),
      actorId,
      reason: "REDEEM",
      idempotencyKey: key,
    });
    if (!posted.created) {
      const saved = await tx.incentiveReward.findUnique({ where: { id: current.id } });
      const matches = (await redemptionRows(tx, current.id)).filter((row) => Number(row.amount).toFixed(2) === requested);
      return { reward: saved || current, redemption: matches.length === 1 ? matches[0] : null, duplicate: true };
    }
    const redemption = await tx.incentiveRedemption.create({
      data: {
        rewardId: current.id,
        orderId: orderId || null,
        amount: requested,
        status: "REDEEMED",
      },
    });
    const remaining = await balanceOf(tx, current.id);
    const updated = await tx.incentiveReward.update({
      where: { id: current.id },
      data: { status: cents(remaining) === 0 ? "REDEEMED" : "PARTIALLY_REDEEMED" },
    });
    await audit(tx, {
      actorId,
      action: "REWARD_REDEEMED",
      campaignId: await campaignIdFor(tx, current.campaignVersionId),
      after: { rewardId: current.id, status: updated.status, amount: requested },
    });
    return { reward: updated, redemption, duplicate: false };
  });
  if (!saved) throw httpError(404, "Reward not found", "REWARD_NOT_FOUND");
  return saved;
}

async function expireDueRewards(tx, { now = new Date(), actorId } = {}) {
  if (!actorId) throw httpError(400, "Expiry requires an actor", "ACTOR_REQUIRED");
  const rows = typeof tx.incentiveReward.findMany === "function"
    ? await tx.incentiveReward.findMany({
      where: { status: { in: ["ISSUED", "PARTIALLY_REDEEMED"] }, couponId: null, expiresAt: { not: null } },
    })
    : tx.incentiveReward.rows || [];
  const expired = [];
  for (const reward of rows) {
    if (reward.couponId || !reward.expiresAt || new Date(reward.expiresAt) > now) continue;
    if (reward.status !== "ISSUED" && reward.status !== "PARTIALLY_REDEEMED") continue;
    const updated = await withRewardLock(tx, reward.id, async () => {
      const current = await tx.incentiveReward.findUnique({ where: { id: reward.id } });
      if (!current || current.couponId || !current.expiresAt || new Date(current.expiresAt) > now) return null;
      if (current.status !== "ISSUED" && current.status !== "PARTIALLY_REDEEMED") return null;
      const remaining = await balanceOf(tx, current.id);
      if (remaining > 0) {
        await postEntry(tx, {
          rewardId: current.id,
          entryType: "EXPIRE",
          amount: (-remaining).toFixed(2),
          actorId,
          reason: "EXPIRED",
          idempotencyKey: `EXPIRE:${current.id}`,
        });
      }
      const saved = await tx.incentiveReward.update({ where: { id: current.id }, data: { status: "EXPIRED" } });
      await audit(tx, {
        actorId,
        action: "REWARD_EXPIRED",
        campaignId: await campaignIdFor(tx, current.campaignVersionId),
        after: { rewardId: current.id, status: "EXPIRED" },
      });
      return saved;
    });
    if (updated) expired.push(updated);
  }
  return expired;
}

module.exports = {
  approveReward,
  expireDueRewards,
  redeemReward,
  rejectReward,
};
