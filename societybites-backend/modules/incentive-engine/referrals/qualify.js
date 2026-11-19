const { httpError } = require("../lib/httpError");
const { qualifyOrder } = require("../events/qualifyOrder");

const OPEN_STATUSES = ["ATTRIBUTED", "PENDING_REVIEW"];
const QUALIFIED_STATUSES = ["QUALIFIED", "PENDING_REVIEW"];

function hasModel(tx) {
  return Boolean(tx && tx.incentiveReferral && typeof tx.incentiveReferral.findMany === "function");
}

function inWindow(row, occurredAt) {
  const start = new Date(row.attributedAt);
  const end = row.windowEndsAt ? new Date(row.windowEndsAt) : null;
  if (Number.isNaN(start.getTime()) || occurredAt < start) return false;
  if (end && occurredAt > end) return false;
  return true;
}

function earlierDate(current, next) {
  if (!current) return next;
  return new Date(current) <= next ? new Date(current) : next;
}

function sellerIdOf(order) {
  const items = order && Array.isArray(order.items) ? order.items : [];
  const sellers = [...new Set(items.map((item) => item && item.listing && item.listing.sellerId).filter(Boolean))];
  return sellers.length === 1 ? sellers[0] : null;
}

function policyOf(version) {
  const snapshot = version && version.snapshot && typeof version.snapshot === "object" ? version.snapshot : {};
  return snapshot.referralPolicy && typeof snapshot.referralPolicy === "object" ? snapshot.referralPolicy : {};
}

function kindEnabled(flags, kind) {
  if (!flags || flags.master !== true || flags.referral !== true) return false;
  if (kind === "BUYER_ACQUISITION") return flags.buyerReferral === true;
  if (kind === "SELLER_ACQUISITION") return flags.sellerReferral === true;
  return false;
}

async function writeAudit(tx, event, action, referral, extra) {
  if (!tx.incentiveAuditLog || typeof tx.incentiveAuditLog.create !== "function") return;
  await tx.incentiveAuditLog.create({
    data: {
      actorId: "system",
      action,
      campaignId: referral ? referral.campaignId : null,
      incentiveEventId: event.id,
      attemptNumber: event.attempts,
      before: referral ? { referralId: referral.id, status: referral.status } : { eventId: event.eventId },
      after: { referralId: referral ? referral.id : null, eventId: event.eventId, ...(extra || {}) },
    },
  });
}

async function lockReferrer(tx, referral) {
  if (!referral.campaignVersionId || typeof tx.$queryRaw !== "function") return;
  await tx.$queryRaw`
    SELECT id FROM "IncentiveReferralCode"
    WHERE "userId" = ${referral.referrerUserId} AND "campaignVersionId" = ${referral.campaignVersionId}
    ORDER BY id
    FOR UPDATE
  `;
}

async function qualifiedCount(tx, referral) {
  return tx.incentiveReferral.count({
    where: {
      referrerUserId: referral.referrerUserId,
      campaignVersionId: referral.campaignVersionId,
      acquisitionKind: referral.acquisitionKind,
      status: { in: QUALIFIED_STATUSES },
    },
  });
}

function completionTime(referral, kind) {
  if (kind === "BUYER_ACQUISITION") return referral.qualifyingOrderAt ? new Date(referral.qualifyingOrderAt) : null;
  if (!referral.sellerEnabledAt || !referral.listingPublishedAt || !referral.qualifyingOrderAt) return null;
  return new Date(Math.max(
    new Date(referral.sellerEnabledAt).getTime(),
    new Date(referral.listingPublishedAt).getTime(),
    new Date(referral.qualifyingOrderAt).getTime()
  ));
}

async function maybeQualify(tx, event, referral, flags) {
  if (referral.status !== "ATTRIBUTED") return referral;
  if (!kindEnabled(flags, referral.acquisitionKind)) {
    await writeAudit(tx, event, "REFERRAL_FLAG_OFF", referral, { status: referral.status });
    return referral;
  }
  const readyAt = completionTime(referral, referral.acquisitionKind);
  if (!readyAt) return referral;
  const version = referral.campaignVersionId && tx.incentiveCampaignVersion
    ? await tx.incentiveCampaignVersion.findUnique({ where: { id: referral.campaignVersionId } })
    : null;
  const policy = policyOf(version);
  const cap = policy.maxQualifiedPerReferrer;
  if (cap != null) {
    await lockReferrer(tx, referral);
    const used = await qualifiedCount(tx, referral);
    if (used >= cap) {
      await writeAudit(tx, event, "REFERRAL_QUALIFICATION_SKIPPED", referral, { reason: "REFERRAL_LIMIT" });
      return referral;
    }
  }
  const nextStatus = policy.requireAdminApproval === true ? "PENDING_REVIEW" : "QUALIFIED";
  const saved = await tx.incentiveReferral.update({
    where: { id: referral.id },
    data: { status: nextStatus, qualifiedAt: readyAt },
  });
  await writeAudit(tx, event, nextStatus === "QUALIFIED" ? "REFERRAL_QUALIFIED" : "REFERRAL_PENDING_REVIEW", saved, {
    status: nextStatus,
  });
  return saved;
}

async function applySellerMilestone(tx, event, referral, occurredAt) {
  if (referral.status !== "ATTRIBUTED") return referral;
  if (!inWindow(referral, occurredAt)) return referral;
  const data = {};
  if (event.type === "USER_BECAME_SELLER") {
    const next = earlierDate(referral.sellerEnabledAt, occurredAt);
    if (!referral.sellerEnabledAt || new Date(referral.sellerEnabledAt).getTime() !== next.getTime()) {
      data.sellerEnabledAt = next;
    }
  }
  if (event.type === "LISTING_PUBLISHED") {
    const next = earlierDate(referral.listingPublishedAt, occurredAt);
    if (!referral.listingPublishedAt || new Date(referral.listingPublishedAt).getTime() !== next.getTime()) {
      data.listingPublishedAt = next;
      data.listingId = event.entityId;
    }
  }
  if (Object.keys(data).length === 0) return referral;
  const saved = await tx.incentiveReferral.update({ where: { id: referral.id }, data });
  await writeAudit(tx, event, "REFERRAL_MILESTONE", saved, data);
  return saved;
}

async function applyOrder(tx, event, order, referral, occurredAt, sellerSide) {
  if (referral.status !== "ATTRIBUTED") return referral;
  if (!order || !qualifyOrder(order).qualified) return referral;
  if (!inWindow(referral, occurredAt)) return referral;
  const sellerId = sellerIdOf(order);
  if (sellerSide) {
    if (!sellerId || sellerId !== referral.referredUserId) return referral;
    if (order.buyerId === sellerId) return referral;
  } else if (order.buyerId !== referral.referredUserId || order.buyerId === sellerId) {
    return referral;
  }
  const current = referral.qualifyingOrderAt ? new Date(referral.qualifyingOrderAt) : null;
  if (current && current <= occurredAt) return referral;
  const saved = await tx.incentiveReferral.update({
    where: { id: referral.id },
    data: { qualifyingOrderId: event.entityId, qualifyingOrderAt: occurredAt },
  });
  await writeAudit(tx, event, "REFERRAL_MILESTONE", saved, { qualifyingOrderId: event.entityId });
  return saved;
}

async function projectProcessedReferral(tx, { event, order, flags }) {
  if (!hasModel(tx) || !event) return;
  if (event.type !== "USER_BECAME_SELLER" && event.type !== "LISTING_PUBLISHED" && event.type !== "ORDER_QUALIFIED") {
    return;
  }
  const occurredAt = new Date(event.occurredAt);
  if (Number.isNaN(occurredAt.getTime())) return;
  if (!kindEnabled(flags, "BUYER_ACQUISITION") && !kindEnabled(flags, "SELLER_ACQUISITION")) {
    await writeAudit(tx, event, "REFERRAL_FLAG_OFF", null, { status: "UNCHANGED" });
    return;
  }

  if (event.type === "ORDER_QUALIFIED") {
    const sellerId = sellerIdOf(order);
    const ids = [...new Set([order && order.buyerId, sellerId].filter(Boolean))];
    if (ids.length === 0) return;
    const rows = await tx.incentiveReferral.findMany({
      where: { referredUserId: { in: ids }, status: "ATTRIBUTED" },
    });
    for (const row of rows) {
      if (!kindEnabled(flags, row.acquisitionKind)) {
        await writeAudit(tx, event, "REFERRAL_FLAG_OFF", row, { status: row.status });
        continue;
      }
      const sellerSide = row.acquisitionKind === "SELLER_ACQUISITION";
      const saved = await applyOrder(tx, event, order, row, occurredAt, sellerSide);
      await maybeQualify(tx, event, saved, flags);
    }
    return;
  }

  if (!event.userId || !kindEnabled(flags, "SELLER_ACQUISITION")) return;
  const rows = await tx.incentiveReferral.findMany({
    where: { referredUserId: event.userId, acquisitionKind: "SELLER_ACQUISITION", status: "ATTRIBUTED" },
  });
  for (const row of rows) {
    const saved = await applySellerMilestone(tx, event, row, occurredAt);
    await maybeQualify(tx, event, saved, flags);
  }
}

function assertOpen(referral, allowed) {
  if (!referral) throw httpError(404, "Referral not found");
  if (!allowed.includes(referral.status)) {
    throw httpError(409, "This referral cannot change", "REFERRAL_NOT_OPEN");
  }
}

async function approveReferral(tx, { id, actorId }) {
  const referral = await tx.incentiveReferral.findUnique({ where: { id } });
  assertOpen(referral, ["PENDING_REVIEW"]);
  const saved = await tx.incentiveReferral.update({ where: { id }, data: { status: "QUALIFIED" } });
  await tx.incentiveAuditLog.create({
    data: {
      actorId,
      action: "REFERRAL_APPROVED",
      campaignId: saved.campaignId,
      before: { referralId: id, status: "PENDING_REVIEW" },
      after: { referralId: id, status: "QUALIFIED" },
    },
  });
  return saved;
}

async function rejectReferral(tx, { id, actorId, reason }) {
  const referral = await tx.incentiveReferral.findUnique({ where: { id } });
  assertOpen(referral, ["PENDING_REVIEW"]);
  const saved = await tx.incentiveReferral.update({
    where: { id },
    data: { status: "DISQUALIFIED", disqualifyReason: reason || "Rejected" },
  });
  await tx.incentiveAuditLog.create({
    data: {
      actorId,
      action: "REFERRAL_REJECTED",
      campaignId: saved.campaignId,
      before: { referralId: id, status: "PENDING_REVIEW" },
      after: { referralId: id, status: "DISQUALIFIED", reason: saved.disqualifyReason },
    },
  });
  return saved;
}

async function disqualifyReferral(tx, { id, actorId, reason }) {
  const referral = await tx.incentiveReferral.findUnique({ where: { id } });
  assertOpen(referral, ["ATTRIBUTED", "PENDING_REVIEW", "QUALIFIED"]);
  const saved = await tx.incentiveReferral.update({
    where: { id },
    data: { status: "DISQUALIFIED", disqualifyReason: reason || "Disqualified" },
  });
  await tx.incentiveAuditLog.create({
    data: {
      actorId,
      action: "REFERRAL_DISQUALIFIED",
      campaignId: saved.campaignId,
      before: { referralId: id, status: referral.status },
      after: { referralId: id, status: "DISQUALIFIED", reason: saved.disqualifyReason },
    },
  });
  return saved;
}

async function expireDueReferrals(tx, { now = new Date(), actorId }) {
  const rows = await tx.incentiveReferral.findMany({
    where: { status: { in: OPEN_STATUSES }, windowEndsAt: { lt: now } },
    take: 50,
  });
  const expired = [];
  for (const row of rows) {
    if (row.acquisitionKind === "SELLER_ACQUISITION" && completionTime(row, row.acquisitionKind)) continue;
    if (row.acquisitionKind === "BUYER_ACQUISITION" && row.qualifyingOrderAt && inWindow(row, new Date(row.qualifyingOrderAt))) {
      continue;
    }
    const saved = await tx.incentiveReferral.update({ where: { id: row.id }, data: { status: "EXPIRED" } });
    await tx.incentiveAuditLog.create({
      data: {
        actorId,
        action: "REFERRAL_EXPIRED",
        campaignId: row.campaignId,
        before: { referralId: row.id, status: row.status },
        after: { referralId: row.id, status: "EXPIRED" },
      },
    });
    expired.push(saved);
  }
  return expired;
}

async function reconcileReferral(tx, referral, { order, now, actorId }) {
  if (!QUALIFIED_STATUSES.includes(referral.status) || !referral.qualifyingOrderId) return referral;
  if (order && qualifyOrder(order).qualified) return referral;
  const windowOpen = !referral.windowEndsAt || new Date(referral.windowEndsAt) >= now;
  const status = windowOpen ? "ATTRIBUTED" : "EXPIRED";
  const saved = await tx.incentiveReferral.update({
    where: { id: referral.id },
    data: { status, qualifyingOrderId: null, qualifyingOrderAt: null },
  });
  await tx.incentiveAuditLog.create({
    data: {
      actorId,
      action: "REFERRAL_QUALIFICATION_REVERSED",
      campaignId: referral.campaignId,
      before: { referralId: referral.id, status: referral.status, qualifyingOrderId: referral.qualifyingOrderId },
      after: { referralId: referral.id, status },
    },
  });
  return saved;
}

module.exports = {
  approveReferral,
  disqualifyReferral,
  expireDueReferrals,
  projectProcessedReferral,
  reconcileReferral,
  rejectReferral,
};
