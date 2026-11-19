const crypto = require("crypto");
const { httpError } = require("../lib/httpError");
const { assertCategoryFlags } = require("../campaign/lifecycle");
const { explainSimulation } = require("../campaign/service");
const { projectProcessedReferral } = require("../referrals/qualify");
const { issueMatchedRewards } = require("../rewards/issue");
const { notifyIncentiveReward } = require("../../../utils/notifications");
const { backoffMs, failureStatus, LEASE_MS, STALE_PENDING_MS } = require("./lifecycle");
const { qualifyOrder } = require("./qualifyOrder");
const { ORDER_TERMINAL_TYPES, validateIngest } = require("./validate");

const PROTECTED_ATTRIBUTE_KEYS = new Set([
  "order.status",
  "order.paymentStatus",
  "order.paymentMethod",
  "order.total",
  "order.subtotal",
  "order.societyId",
  "order.sellerId",
  "order.itemCount",
]);

function toIso(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function presentEvent(row) {
  if (!row) return null;
  return {
    id: row.id,
    eventId: row.eventId,
    schemaVersion: row.schemaVersion,
    type: row.type,
    entityType: row.entityType,
    entityId: row.entityId,
    userId: row.userId || null,
    occurredAt: toIso(row.occurredAt),
    payload: row.payload || {},
    status: row.status,
    attempts: row.attempts,
    nextAttemptAt: toIso(row.nextAttemptAt),
    lastError: row.lastError || null,
    createdAt: toIso(row.createdAt),
    processedAt: toIso(row.processedAt),
    claimedAt: toIso(row.claimedAt),
    claimedBy: row.claimedBy || null,
  };
}

function conflictKind(error) {
  if (!error || error.code !== "P2002") return null;
  if (error.constraint === "orderTerminal" || error.constraint === "eventId") return error.constraint;
  return null;
}

async function ingestEvent(repository, body) {
  const input = validateIngest(body);
  const row = {
    eventId: input.eventId,
    schemaVersion: input.schemaVersion,
    type: input.type,
    entityType: input.entityType,
    entityId: input.entityId,
    userId: input.userId,
    occurredAt: input.occurredAt,
    payload: input.payload,
    status: "PENDING",
    attempts: 0,
  };
  try {
    const created = await repository.insertEvent(row);
    return { created: true, event: presentEvent(created) };
  } catch (error) {
    const kind = conflictKind(error);
    if (!kind) throw error;
    const existing = kind === "orderTerminal"
      ? await repository.findOrderTerminal(input.entityId)
      : await repository.findByEventId(input.eventId);
    if (existing && existing.type === input.type && existing.eventId === input.eventId) {
      return { created: false, event: presentEvent(existing) };
    }
    if (existing && ORDER_TERMINAL_TYPES.includes(existing.type) && ORDER_TERMINAL_TYPES.includes(input.type)) {
      throw httpError(409, "An order can have only one terminal incentive event", "ORDER_TERMINAL_CONFLICT");
    }
    throw error;
  }
}

function buildAttributes(event, order) {
  const attributes = { "event.type": event.type };
  const payload = event.payload && typeof event.payload === "object" ? event.payload : {};
  for (const [key, value] of Object.entries(payload)) {
    if (!PROTECTED_ATTRIBUTE_KEYS.has(key)) attributes[key] = value;
  }
  if (!order) return attributes;
  attributes["order.status"] = order.status;
  attributes["order.paymentStatus"] = order.paymentStatus || "pending";
  attributes["order.paymentMethod"] = order.paymentMethod || null;
  attributes["order.total"] = order.total;
  attributes["order.subtotal"] = order.subtotal;
  attributes["order.societyId"] = order.societyId;
  const listing = order.items && order.items[0] && order.items[0].listing;
  if (listing && listing.sellerId) attributes["order.sellerId"] = listing.sellerId;
  if (Array.isArray(order.items)) {
    attributes["order.itemCount"] = order.items.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
  }
  return attributes;
}

async function permanentOrderOutcome(event, loadOrder) {
  if (event.entityType !== "order") return null;
  const order = await loadOrder(event.entityId);
  if (!order) return { status: "SKIPPED", reasonCodes: ["ENTITY_NOT_FOUND"] };
  if (event.type === "ORDER_QUALIFIED") {
    const result = qualifyOrder(order);
    if (!result.qualified) return { status: "SKIPPED", reasonCodes: [result.reason], order };
    return { order };
  }
  if (event.type === "ORDER_CANCELLED" && order.status !== "cancelled") {
    return { status: "SKIPPED", reasonCodes: ["ORDER_STATUS_MISMATCH"], order };
  }
  if (event.type === "ORDER_REJECTED" && order.status !== "rejected") {
    return { status: "SKIPPED", reasonCodes: ["ORDER_STATUS_MISMATCH"], order };
  }
  return { order };
}

function matchCampaigns(campaigns, event, attributes, flags) {
  const matches = [];
  for (const campaign of campaigns) {
    try {
      assertCategoryFlags(campaign, flags);
    } catch (error) {
      if (error && error.statusCode === 403) {
        matches.push({
          campaignId: campaign.id,
          versionId: campaign.version.id,
          passed: false,
          reasonCodes: [error.code || "CATEGORY_DISABLED"],
        });
        continue;
      }
      throw error;
    }
    const explanation = explainSimulation(campaign.version.snapshot, attributes);
    matches.push({
      campaignId: campaign.id,
      versionId: campaign.version.id,
      passed: explanation.passed === true,
      ready: explanation.ready === true,
      reasonCodes: (explanation.failures || []).map((failure) => failure.code),
    });
  }
  return matches;
}

function auditRecord(event, patch, actorId) {
  const primary = (patch.matches || []).find((match) => match.passed) || (patch.matches || [])[0] || null;
  return {
    actorId: actorId || "system",
    action: patch.action,
    campaignId: primary ? primary.campaignId : null,
    incentiveEventId: event.id,
    attemptNumber: event.attempts,
    before: { status: "PROCESSING", eventId: event.eventId, type: event.type },
    after: {
      eventId: event.eventId,
      type: event.type,
      outcome: patch.status,
      reasonCodes: patch.reasonCodes || [],
      matches: patch.matches || [],
      processedAt: patch.processedAt ? patch.processedAt.toISOString() : null,
    },
  };
}

async function saveOutcome(repository, event, token, patch) {
  try {
    return await repository.finish(event.id, token, {
      ...patch,
      audit: auditRecord(event, patch, patch.actorId),
    });
  } catch (error) {
    if (error && error.code === "P2002") {
      const current = await repository.findById(event.id);
      if (!current || current.claimToken !== token) return { applied: false, stale: true };
    }
    throw error;
  }
}

async function evaluateClaimed(repository, event, { token, flags, now, loadOrder, actorId, couponWriter }) {
  try {
    const orderOutcome = await permanentOrderOutcome(event, loadOrder);
    if (orderOutcome && orderOutcome.status === "SKIPPED") {
      const saved = await saveOutcome(repository, event, token, {
        status: "SKIPPED",
        reasonCodes: orderOutcome.reasonCodes,
        matches: [],
        processedAt: now,
        nextAttemptAt: null,
        lastError: orderOutcome.reasonCodes[0],
        action: "EVENT_SKIPPED",
        actorId,
      });
      return { id: event.id, status: saved.applied ? "SKIPPED" : "STALE", applied: saved.applied };
    }
    const attributes = buildAttributes(event, orderOutcome && orderOutcome.order);
    const campaigns = await repository.listEligibleCampaigns(event.type, now);
    const matches = matchCampaigns(campaigns, event, attributes, flags);
    const freshRewards = [];
    const saved = await saveOutcome(repository, event, token, {
      status: "PROCESSED",
      reasonCodes: [],
      matches,
      processedAt: now,
      nextAttemptAt: null,
      lastError: null,
      action: "EVENT_PROCESSED",
      actorId,
      projectReferral: (tx) => projectProcessedReferral(tx, {
        event,
        order: orderOutcome && orderOutcome.order,
        flags,
        now,
      }),
      projectRewards: async (tx) => {
        const result = await issueMatchedRewards(tx, {
          event,
          matches,
          campaigns,
          flags,
          now,
          order: orderOutcome && orderOutcome.order,
          couponWriter,
        });
        if (result && Array.isArray(result.fresh)) freshRewards.push(...result.fresh);
        return result;
      },
    });
    if (saved.applied) {
      for (const reward of freshRewards) notifyIncentiveReward(reward);
    }
    return { id: event.id, status: saved.applied ? "PROCESSED" : "STALE", applied: saved.applied, matches };
  } catch (error) {
    const status = failureStatus(event.attempts);
    const saved = await saveOutcome(repository, event, token, {
      status,
      reasonCodes: ["PROCESSING_ERROR"],
      matches: [],
      processedAt: null,
      nextAttemptAt: status === "DEAD" ? null : new Date(now.getTime() + backoffMs(event.attempts)),
      lastError: String(error && error.message ? error.message : error).slice(0, 500),
      action: status === "DEAD" ? "EVENT_DEAD" : "EVENT_FAILED",
      actorId,
    });
    if (!saved.applied) return { id: event.id, status: "STALE", applied: false };
    return { id: event.id, status, applied: true, error: String(error && error.message ? error.message : error) };
  }
}

async function processDue(repository, { now = new Date(), workerId, limit = 20, loadOrder } = {}) {
  const flags = await repository.readFlags();
  if (!flags || flags.master !== true) {
    return { code: "ENGINE_DISABLED", processed: [] };
  }
  const bounded = Math.min(Math.max(Number(limit) || 20, 1), 50);
  const due = await repository.findDue(now, bounded);
  const processed = [];
  const owner = workerId || crypto.randomUUID();
  for (const candidate of due) {
    const claim = await repository.claim(candidate.id, { now, workerId: owner });
    if (claim.blocked) return { code: "ENGINE_DISABLED", processed };
    if (!claim.claimed) continue;
    processed.push(
      await evaluateClaimed(repository, claim.event, {
        token: claim.token,
        flags: claim.flags,
        now,
        loadOrder: loadOrder || ((id) => repository.loadOrder(id)),
        actorId: "system",
      })
    );
  }
  return { processed };
}

async function recoverExpired(repository, { now = new Date(), actorId, leaseMs = LEASE_MS } = {}) {
  if (!actorId) throw httpError(400, "Recovery requires an actor", "ACTOR_REQUIRED");
  const expired = await repository.findExpired(now, leaseMs);
  const recovered = [];
  for (const event of expired) {
    const status = failureStatus(event.attempts);
    const saved = await saveOutcome(repository, event, event.claimToken, {
      status,
      reasonCodes: ["LEASE_EXPIRED"],
      matches: [],
      processedAt: null,
      nextAttemptAt: status === "DEAD" ? null : new Date(now.getTime() + backoffMs(event.attempts)),
      lastError: "Claim lease expired",
      action: "EVENT_RECOVERED",
      actorId,
    });
    recovered.push({ id: event.id, status: saved.applied ? status : "STALE", applied: saved.applied });
  }
  return { recovered };
}

async function replayEvent(repository, { id, actorId }) {
  if (!actorId) throw httpError(400, "Replay requires an actor", "ACTOR_REQUIRED");
  const result = await repository.replay(id, actorId);
  if (result.missing) throw httpError(404, "Incentive event not found");
  if (result.rejected) throw httpError(409, "Only a failed, dead, or skipped event can be replayed", "REPLAY_NOT_ALLOWED");
  return { event: presentEvent(result.event) };
}

async function getEvent(repository, id) {
  const event = await repository.findById(id);
  if (!event) throw httpError(404, "Incentive event not found");
  return { event: presentEvent(event) };
}

async function listEvents(repository, query) {
  const limit = Math.min(Math.max(Number(query && query.limit) || 50, 1), 50);
  const status = query && query.status ? String(query.status) : undefined;
  const type = query && query.type ? String(query.type) : undefined;
  const cursor = query && query.cursor ? String(query.cursor) : undefined;
  const rows = await repository.listEvents({ status, type, cursor, limit: limit + 1 });
  const page = rows.slice(0, limit);
  return {
    events: page.map(presentEvent),
    nextCursor: rows.length > limit ? page[page.length - 1].id : null,
  };
}

async function reconciliationView(repository, now = new Date()) {
  const report = await repository.findReconciliation(now, STALE_PENDING_MS);
  return {
    expired: report.expired.map(presentEvent),
    dead: report.dead.map(presentEvent),
    failedDue: report.failedDue.map(presentEvent),
    stalePending: report.stalePending.map(presentEvent),
  };
}

module.exports = {
  PROTECTED_ATTRIBUTE_KEYS,
  buildAttributes,
  evaluateClaimed,
  getEvent,
  ingestEvent,
  listEvents,
  presentEvent,
  processDue,
  reconciliationView,
  recoverExpired,
  replayEvent,
};
