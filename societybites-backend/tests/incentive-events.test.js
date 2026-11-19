const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");

const { requireAdmin, requireSuperAdmin } = require("../middleware/requireAdmin");
const { LEASE_MS, isDue, leaseExpired } = require("../modules/incentive-engine/events/lifecycle");
const { qualifyOrder } = require("../modules/incentive-engine/events/qualifyOrder");
const { ORDER_TERMINAL_TYPES } = require("../modules/incentive-engine/events/validate");
const { createPrismaEventRepository } = require("../modules/incentive-engine/events/repository");
const {
  ingestEvent,
  processDue,
  recoverExpired,
  replayEvent,
} = require("../modules/incentive-engine/events/process");
const { createEventsRouter } = require("../modules/incentive-engine/routes/adminEvents");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function createMemoryEventRepository() {
  const events = new Map();
  const audits = [];
  const campaigns = [];
  const orders = new Map();
  let masterValue = null;
  let flags = {
    master: false,
    issuance: false,
    redemption: false,
    referral: false,
    buyerReferral: false,
    sellerReferral: false,
    promotional: false,
  };
  let claims = 0;
  let evaluationFailures = 0;

  function clone(row) {
    return JSON.parse(JSON.stringify(row));
  }

  return {
    audits,
    campaigns,
    orders,
    setFlags(next) {
      if (next && Object.prototype.hasOwnProperty.call(next, "master")) {
        if (next.master === true) masterValue = "true";
        else if (next.master === false) masterValue = "false";
        else if (next.master == null) masterValue = null;
        else masterValue = String(next.master);
      }
      const master = typeof masterValue === "string" && masterValue.trim() === "true";
      flags = { ...flags, ...next, master };
    },
    claimCount() {
      return claims;
    },
    failNext(count) {
      evaluationFailures = count;
    },
    async readFlags() {
      return { ...flags };
    },
    async findById(id) {
      return events.has(id) ? clone(events.get(id)) : null;
    },
    async findByEventId(eventId) {
      for (const row of events.values()) if (row.eventId === eventId) return clone(row);
      return null;
    },
    async findOrderTerminal(entityId) {
      for (const row of events.values()) {
        if (row.entityType === "order" && row.entityId === entityId && ORDER_TERMINAL_TYPES.includes(row.type)) {
          return clone(row);
        }
      }
      return null;
    },
    async insertEvent(row) {
      for (const existing of events.values()) {
        if (existing.eventId === row.eventId) {
          const error = new Error("duplicate event");
          error.code = "P2002";
          error.constraint = "eventId";
          throw error;
        }
      }
      if (row.entityType === "order" && ORDER_TERMINAL_TYPES.includes(row.type)) {
        for (const existing of events.values()) {
          if (existing.entityType === "order" && existing.entityId === row.entityId && ORDER_TERMINAL_TYPES.includes(existing.type)) {
            const error = new Error("duplicate order terminal");
            error.code = "P2002";
            error.constraint = "orderTerminal";
            throw error;
          }
        }
      }
      const stored = {
        ...row,
        id: crypto.randomUUID(),
        payload: row.payload || {},
        attempts: 0,
        createdAt: new Date(),
        claimToken: null,
        claimedAt: null,
        claimedBy: null,
        nextAttemptAt: null,
        lastError: null,
        processedAt: null,
      };
      events.set(stored.id, stored);
      return clone(stored);
    },
    async findDue(now, limit) {
      return [...events.values()].filter((row) => isDue(row, now)).slice(0, limit).map(clone);
    },
    async claim(id, { now, workerId }) {
      if (!(typeof masterValue === "string" && masterValue.trim() === "true")) {
        return { blocked: true, flags: { ...flags, master: false } };
      }
      const event = events.get(id);
      if (!event || !isDue(event, now)) return { claimed: false, flags: { ...flags } };
      claims += 1;
      event.status = "PROCESSING";
      event.attempts += 1;
      event.claimToken = crypto.randomUUID();
      event.claimedAt = now;
      event.claimedBy = workerId;
      event.lastError = null;
      return { claimed: true, event: clone(event), token: event.claimToken, flags: { ...flags } };
    },
    async finish(id, token, patch) {
      const event = events.get(id);
      if (!event || event.status !== "PROCESSING" || event.claimToken !== token) return { applied: false };
      if (typeof patch.projectReferral === "function") await patch.projectReferral(null);
      if (typeof patch.projectRewards === "function") await patch.projectRewards(null);
      const duplicate = audits.some(
        (row) => row.incentiveEventId === id && row.action === patch.audit.action && row.attemptNumber === patch.audit.attemptNumber
      );
      if (duplicate) return { applied: false };
      event.status = patch.status;
      event.claimToken = null;
      event.claimedAt = null;
      event.claimedBy = null;
      event.nextAttemptAt = patch.nextAttemptAt || null;
      event.lastError = patch.lastError || null;
      event.processedAt = patch.processedAt || null;
      audits.push({ ...patch.audit, id: crypto.randomUUID() });
      return { applied: true };
    },
    async listEligibleCampaigns(eventType, now) {
      if (evaluationFailures > 0) {
        evaluationFailures -= 1;
        throw new Error("evaluation failed");
      }
      return campaigns
        .filter((campaign) => {
          if (campaign.status !== "ACTIVE" && campaign.status !== "SCHEDULED") return false;
          if (campaign.endsAt && new Date(campaign.endsAt) <= now) return false;
          if (campaign.status === "SCHEDULED" && new Date(campaign.startsAt) > now) return false;
          const triggers = campaign.version.snapshot.triggers || [];
          return triggers.some((trigger) => trigger.eventType === eventType);
        })
        .map(clone);
    },
    async loadOrder(id) {
      return orders.has(id) ? clone(orders.get(id)) : null;
    },
    async listEvents() {
      return [...events.values()].map(clone);
    },
    async findExpired(now, leaseMs) {
      return [...events.values()].filter((row) => leaseExpired(row, now, leaseMs)).map(clone);
    },
    async findReconciliation(now, staleMs) {
      const all = [...events.values()];
      return {
        dead: all.filter((row) => row.status === "DEAD").map(clone),
        failedDue: all.filter((row) => row.status === "FAILED" && isDue(row, now)).map(clone),
        stalePending: all.filter((row) => row.status === "PENDING" && new Date(row.createdAt).getTime() <= now.getTime() - staleMs).map(clone),
        expired: all.filter((row) => leaseExpired(row, now)).map(clone),
      };
    },
    async replay(id, actorId) {
      const current = events.get(id);
      if (!current) return { missing: true };
      if (!["FAILED", "DEAD", "SKIPPED"].includes(current.status)) return { rejected: true, event: clone(current) };
      const previous = current.status;
      current.status = "PENDING";
      current.nextAttemptAt = null;
      current.claimToken = null;
      current.claimedAt = null;
      current.claimedBy = null;
      current.lastError = null;
      current.processedAt = null;
      audits.push({
        id: crypto.randomUUID(),
        actorId,
        action: "EVENT_REPLAY",
        incentiveEventId: id,
        attemptNumber: null,
        before: { status: previous },
        after: { status: "PENDING", outcome: "REPLAYED" },
      });
      return { event: clone(current) };
    },
    stored(id) {
      return events.get(id);
    },
  };
}

function order(overrides) {
  return {
    id: "order-1",
    status: "completed",
    type: "regular",
    paymentMethod: "upi",
    paymentStatus: "seller_confirmed",
    paymentProvider: "direct_upi",
    societyId: "society-a",
    fulfilmentMethod: "pickup",
    deliveryCharge: 0,
    deliveryCashConfirmedAt: null,
    total: 120,
    subtotal: 100,
    items: [{ quantity: 1, listing: { societyId: "society-a", sellerId: "seller-1" } }],
    ...overrides,
  };
}

function readyCampaign() {
  return {
    id: "camp-1",
    category: "REPEAT_ORDER",
    status: "ACTIVE",
    startsAt: "2026-01-01T00:00:00.000Z",
    endsAt: "2026-12-31T00:00:00.000Z",
    version: {
      id: "ver-1",
      publishedAt: "2026-06-01T00:00:00.000Z",
      snapshot: {
        audiences: [{ kind: "ALL_USERS", payload: {} }],
        triggers: [{ eventType: "ORDER_QUALIFIED", processor: "NOT_IMPLEMENTED" }],
        eligibility: "AUDIENCE_AND_TRIGGER_ONLY",
        rules: null,
        rewards: [{ slot: "buyer", recipientRole: "BUYER", rewardType: "FIXED_COUPON", amount: "20.00" }],
        budget: { currency: "INR", amountCap: "1000.00", issuedAmount: "0.00" },
      },
    },
  };
}

async function expectError(work, statusCode, code) {
  try {
    await work();
  } catch (error) {
    assert(error.statusCode === statusCode, `expected ${statusCode} but got ${error.statusCode}`);
    if (code) assert(error.code === code, `expected ${code} but got ${error.code}`);
    return error;
  }
  throw new Error(`expected ${statusCode} ${code || ""}`);
}

async function testValidationAndIdempotency() {
  const repo = createMemoryEventRepository();
  await expectError(() => ingestEvent(repo, { type: "NOT_AN_EVENT", entityId: "u1", occurredAt: "2026-06-01T00:00:00.000Z" }), 400, "EVENT_TYPE_INVALID");
  await expectError(
    () => ingestEvent(repo, { type: "USER_REGISTERED", entityId: "u1", occurredAt: "2026-06-01T00:00:00.000Z", payload: { sql: "drop table" } }),
    400,
    "EVENT_INVALID"
  );
  const first = await ingestEvent(repo, { type: "USER_REGISTERED", entityId: "user-1", occurredAt: "2026-06-01T00:00:00.000Z" });
  const second = await ingestEvent(repo, { type: "USER_REGISTERED", entityId: "user-1", occurredAt: "2026-06-01T00:00:00.000Z" });
  assert(first.created === true, "first ingest creates");
  assert(second.created === false, "duplicate ingest does not create");
  assert(first.event.id === second.event.id, "duplicate returns the same event");
  assert(repo.audits.length === 0, "ingestion does not write an audit outcome");

  await ingestEvent(repo, { type: "ORDER_QUALIFIED", entityId: "order-9", occurredAt: "2026-06-01T00:00:00.000Z" });
  await expectError(
    () => ingestEvent(repo, { type: "ORDER_CANCELLED", entityId: "order-9", occurredAt: "2026-06-01T00:00:00.000Z" }),
    409,
    "ORDER_TERMINAL_CONFLICT"
  );
  const same = await ingestEvent(repo, { type: "ORDER_QUALIFIED", entityId: "order-9", occurredAt: "2026-06-01T00:00:00.000Z" });
  assert(same.created === false, "same order terminal event is idempotent");
  assert([...repo.orders.keys()].length === 0, "order map stays unused");
}

async function testQualification() {
  assert(qualifyOrder(order()).qualified === true, "direct UPI seller confirmation qualifies");
  assert(qualifyOrder(order({ paymentStatus: "paid" })).qualified === true, "direct UPI paid qualifies");
  assert(qualifyOrder(order({ paymentStatus: "buyer_marked_paid" })).qualified === false, "buyer marked paid does not qualify");
  assert(qualifyOrder(order({ paymentMethod: "cash", paymentStatus: "paid", paymentProvider: null })).qualified === true, "cash paid qualifies");
  assert(qualifyOrder(order({ paymentMethod: "cash", paymentStatus: "pending", paymentProvider: null })).qualified === false, "unpaid cash does not qualify");
  assert(qualifyOrder(order({ paymentProvider: "cashfree", paymentStatus: "paid" })).qualified === true, "cashfree paid qualifies");
  assert(qualifyOrder(order({ paymentProvider: "cashfree", paymentStatus: "seller_confirmed" })).qualified === false, "cashfree without paid does not qualify");
  const split = order({
    paymentMethod: "upi",
    paymentStatus: "seller_confirmed",
    societyId: "buyer-society",
    fulfilmentMethod: "seller_delivery",
    deliveryCharge: 20,
    deliveryCashConfirmedAt: "2026-06-01T00:00:00.000Z",
    items: [{ quantity: 1, listing: { societyId: "kitchen-society", sellerId: "seller-1" } }],
  });
  assert(qualifyOrder(split).qualified === true, "food and delivery confirmation qualifies");
  assert(qualifyOrder({ ...split, deliveryCashConfirmedAt: null }).qualified === false, "unconfirmed delivery cash does not qualify");
  assert(qualifyOrder(order({ status: "cancelled", paymentStatus: "seller_confirmed" })).qualified === false, "cancelled never qualifies");
  assert(qualifyOrder(order({ status: "rejected", paymentStatus: "paid" })).qualified === false, "rejected never qualifies");
  assert(qualifyOrder(order({ status: "ready" })).qualified === false, "ready does not qualify");
  for (const status of ["pending", "accepted", "preparing", "picked_up"]) {
    assert(qualifyOrder(order({ status })).qualified === false, `${status} does not qualify`);
    assert(qualifyOrder(order({ status })).reason === "ORDER_NOT_COMPLETED", `${status} is not completed`);
  }
  assert(qualifyOrder(order({ paymentStatus: "failed" })).qualified === false, "a failed payment does not qualify");
}

async function testMasterAndMatching() {
  const repo = createMemoryEventRepository();
  const now = new Date("2026-06-15T00:00:00.000Z");
  const ingested = await ingestEvent(repo, { type: "ORDER_QUALIFIED", entityId: "order-1", occurredAt: now.toISOString() });
  repo.orders.set("order-1", order());
  repo.campaigns.push(readyCampaign());
  repo.campaigns.push({ ...readyCampaign(), id: "draft", status: "DRAFT" });
  const blocked = await processDue(repo, { now, loadOrder: (id) => repo.loadOrder(id) });
  assert(blocked.code === "ENGINE_DISABLED", "master off blocks processing");
  assert(repo.stored(ingested.event.id).status === "PENDING", "master off leaves the event pending");
  assert(repo.stored(ingested.event.id).attempts === 0, "master off does not consume an attempt");
  assert(repo.claimCount() === 0, "master off does not claim");
  assert(repo.audits.length === 0, "unclaimed event has no audit");

  repo.setFlags({ master: true });
  const processed = await processDue(repo, { now, loadOrder: (id) => repo.loadOrder(id) });
  assert(processed.processed.length === 1, "one event processed");
  assert(processed.processed[0].status === "PROCESSED", "matching campaign is processed");
  assert(processed.processed[0].matches.length === 1, "draft campaign is ignored");
  assert(processed.processed[0].matches[0].passed === true, "ready all-user campaign matches");
  assert(repo.audits.length === 1, "one processing audit");
  assert(repo.audits[0].incentiveEventId === ingested.event.id, "audit links the event");
  assert(repo.audits[0].attemptNumber === 1, "audit links the attempt");
  assert(repo.audits[0].action === "EVENT_PROCESSED", "processed action");
  assert(repo.audits[0].actorId === "system", "automatic processing actor is system");

  const unqualified = await ingestEvent(repo, { type: "ORDER_QUALIFIED", entityId: "order-2", occurredAt: now.toISOString() });
  repo.orders.set("order-2", order({ status: "cancelled" }));
  const skipped = await processDue(repo, { now, loadOrder: (id) => repo.loadOrder(id) });
  assert(skipped.processed[0].status === "SKIPPED", "cancelled order is skipped");
  assert(repo.stored(unqualified.event.id).status === "SKIPPED", "skip is stored");
}

async function testRetryFenceAndRecovery() {
  const repo = createMemoryEventRepository();
  const now = new Date("2026-06-15T00:00:00.000Z");
  repo.setFlags({ master: true });
  const ingested = await ingestEvent(repo, { type: "USER_REGISTERED", entityId: "user-9", occurredAt: now.toISOString() });
  repo.failNext(1);
  const failed = await processDue(repo, { now, loadOrder: async () => null });
  assert(failed.processed[0].status === "FAILED", "evaluation error is retryable");
  const stored = repo.stored(ingested.event.id);
  assert(stored.attempts === 1, "failure consumes one attempt");
  assert(stored.nextAttemptAt.getTime() - now.getTime() === 30000, "first retry waits 30 seconds");
  assert(repo.audits[0].action === "EVENT_FAILED", "failure audit");

  stored.nextAttemptAt = new Date(now.getTime() - 1000);
  repo.failNext(7);
  let cursor = new Date(now.getTime() + 60 * 1000);
  for (let i = 0; i < 7; i += 1) {
    await processDue(repo, { now: cursor, loadOrder: async () => null });
    cursor = new Date(cursor.getTime() + 2 * 60 * 60 * 1000);
  }
  assert(repo.stored(ingested.event.id).status === "DEAD", "eighth failure is dead");
  assert(repo.stored(ingested.event.id).attempts === 8, "dead letter keeps eight attempts");

  const replayed = await replayEvent(repo, { id: ingested.event.id, actorId: "admin-1" });
  assert(replayed.event.status === "PENDING", "replay returns the event to pending");
  assert(replayed.event.attempts === 8, "replay keeps the eight attempts");
  assert(repo.audits.some((row) => row.action === "EVENT_REPLAY" && row.actorId === "admin-1"), "replay records the super admin");
  repo.failNext(1);
  const replayedFailure = await processDue(repo, { now: cursor, loadOrder: async () => null });
  assert(replayedFailure.processed[0].status === "DEAD", "a failed claim after the cap is dead again");
  assert(repo.stored(ingested.event.id).attempts === 9, "the claim after replay increments");
  const deadAudits = repo.audits.filter((row) => row.action === "EVENT_DEAD" && row.incentiveEventId === ingested.event.id);
  assert(deadAudits.length === 2, "each dead outcome has its own audit");
  assert(deadAudits.some((row) => row.attemptNumber === 8) && deadAudits.some((row) => row.attemptNumber === 9), "dead audits use different attempts");

  const again = await ingestEvent(repo, { type: "USER_REGISTERED", entityId: "user-8", occurredAt: now.toISOString() });
  const claimA = await repo.claim(again.event.id, { now, workerId: "worker-a" });
  const claimB = await repo.claim(again.event.id, { now, workerId: "worker-b" });
  assert(claimA.claimed === true && claimB.claimed === false, "second claim loses");
  assert(repo.stored(again.event.id).attempts === 1, "concurrent claims increment once");
  const tokenA = claimA.token;
  repo.stored(again.event.id).claimedAt = new Date(now.getTime() - LEASE_MS - 1000);
  const recovered = await recoverExpired(repo, { now, actorId: "admin-2" });
  assert(recovered.recovered[0].applied === true, "expired claim is recovered");
  assert(repo.stored(again.event.id).attempts === 1, "recovery does not add an attempt");
  assert(repo.audits.some((row) => row.action === "EVENT_RECOVERED" && row.actorId === "admin-2"), "recovery records the actor");
  repo.stored(again.event.id).nextAttemptAt = new Date(now.getTime() - 1000);
  const newer = await processDue(repo, { now, loadOrder: async () => null });
  assert(newer.processed[0].status === "PROCESSED", "newer worker processes the event");
  const auditsBeforeStale = repo.audits.length;
  const stale = await repo.finish(again.event.id, tokenA, {
    status: "SKIPPED",
    audit: { action: "EVENT_SKIPPED", attemptNumber: 1, actorId: "worker-a", incentiveEventId: again.event.id },
  });
  assert(stale.applied === false, "stale worker cannot overwrite");
  assert(repo.stored(again.event.id).status === "PROCESSED", "newer outcome remains");
  assert(repo.audits.length === auditsBeforeStale, "stale worker does not add an audit");
  const secondRecovery = await recoverExpired(repo, { now: new Date(now.getTime() + LEASE_MS + 5000), actorId: "admin-2" });
  assert(secondRecovery.recovered.length === 0, "a second recovery finds nothing to change");
}

function testUser(req, res, next) {
  const role = req.headers["x-role"];
  if (!role) return res.status(401).json({ error: "Missing or invalid Authorization header" });
  req.user = { id: "admin-1", role, consoleAdmin: req.headers["x-console"] === "1" };
  next();
}

function jsonRequest(server, { method, requestPath, role, consoleAdmin, body }) {
  const payload = body == null ? null : JSON.stringify(body);
  const headers = { Accept: "application/json" };
  if (role) headers["x-role"] = role;
  if (consoleAdmin) headers["x-console"] = "1";
  if (payload) {
    headers["Content-Type"] = "application/json";
    headers["Content-Length"] = Buffer.byteLength(payload);
  }
  const address = server.address();
  return new Promise((resolve, reject) => {
    const request = http.request(
      { hostname: "127.0.0.1", port: address.port, path: requestPath, method, headers },
      (response) => {
        let data = "";
        response.on("data", (chunk) => (data += chunk));
        response.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {
            json = null;
          }
          resolve({ status: response.statusCode, json });
        });
      }
    );
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

async function testHttpPermissions() {
  const repo = createMemoryEventRepository();
  repo.setFlags({ master: true });
  const ingested = await ingestEvent(repo, { type: "USER_REGISTERED", entityId: "user-http", occurredAt: "2026-06-01T00:00:00.000Z" });
  await processDue(repo, { now: new Date("2026-06-15T00:00:00.000Z"), loadOrder: async () => null });
  const app = express();
  app.use(express.json());
  app.use(
    "/incentive/admin",
    createEventsRouter({
      repository: repo,
      requireUser: testUser,
      requireAdmin,
      requireSuperAdmin,
    })
  );
  const server = await new Promise((resolve) => {
    const listening = http.createServer(app);
    listening.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const missing = await jsonRequest(server, { method: "POST", requestPath: "/incentive/admin/events/process-due", body: {} });
    assert(missing.status === 401, "events require a signed-in user");
    const buyer = await jsonRequest(server, { method: "POST", requestPath: "/incentive/admin/events/process-due", role: "buyer", body: {} });
    assert(buyer.status === 403, "buyer cannot process events");
    const consoleAdmin = await jsonRequest(server, {
      method: "POST",
      requestPath: `/incentive/admin/events/${ingested.event.id}/replay`,
      role: "admin",
      consoleAdmin: true,
      body: {},
    });
    assert(consoleAdmin.status === 403, "console admin cannot replay");
    const replayed = await jsonRequest(server, {
      method: "POST",
      requestPath: `/incentive/admin/events/${ingested.event.id}/replay`,
      role: "super_admin",
      body: {},
    });
    assert(replayed.status === 409, "processed event cannot be replayed");
    const off = await jsonRequest(server, { method: "POST", requestPath: "/incentive/admin/events/process-due", role: "super_admin", body: {} });
    repo.setFlags({ master: false });
    const disabled = await jsonRequest(server, { method: "POST", requestPath: "/incentive/admin/events/process-due", role: "super_admin", body: {} });
    assert(disabled.status === 403 && disabled.json.code === "ENGINE_DISABLED", "http processing reports the master switch");
    assert(off.status === 200, "processing with the switch on returns the batch");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function testClaimAndReplayAttempts() {
  const repo = createMemoryEventRepository();
  const now = new Date("2026-06-15T00:00:00.000Z");
  const ingested = await ingestEvent(repo, { type: "USER_REGISTERED", entityId: "user-claim", occurredAt: now.toISOString() });
  const missing = await repo.claim(ingested.event.id, { now, workerId: "worker-1" });
  assert(missing.blocked === true && missing.claimed !== true, "missing master blocks the claim");
  repo.setFlags({ master: false });
  const off = await repo.claim(ingested.event.id, { now, workerId: "worker-1" });
  assert(off.blocked === true, "false master blocks the claim");
  repo.setFlags({ master: " false " });
  const padded = await repo.claim(ingested.event.id, { now, workerId: "worker-1" });
  assert(padded.blocked === true, "whitespace-padded false blocks the claim");
  repo.setFlags({ master: "TRUE" });
  const wrongCase = await repo.claim(ingested.event.id, { now, workerId: "worker-1" });
  assert(wrongCase.blocked === true, "uppercase TRUE blocks the claim");
  assert(repo.stored(ingested.event.id).status === "PENDING", "blocked claims leave the event pending");
  assert(repo.stored(ingested.event.id).attempts === 0, "blocked claims do not increment attempts");
  repo.setFlags({ master: " true " });
  const claimed = await repo.claim(ingested.event.id, { now, workerId: "worker-1" });
  assert(claimed.claimed === true, "trimmed true allows the claim");
  assert(repo.stored(ingested.event.id).attempts === 1, "a successful claim increments attempts");
  assert(repo.stored(ingested.event.id).claimToken === claimed.token, "claim stores its token");

  repo.stored(ingested.event.id).status = "FAILED";
  repo.stored(ingested.event.id).attempts = 3;
  repo.stored(ingested.event.id).claimToken = null;
  const replayed = await replayEvent(repo, { id: ingested.event.id, actorId: "admin-1" });
  assert(replayed.event.attempts === 3, "replay preserves the previous attempt count");
  const next = await repo.claim(ingested.event.id, { now, workerId: "worker-2" });
  assert(next.claimed === true, "replayed event can be claimed");
  assert(repo.stored(ingested.event.id).attempts === 4, "the next claim increments the preserved count");
  const firstFinish = await repo.finish(ingested.event.id, next.token, {
    status: "FAILED",
    nextAttemptAt: new Date(now.getTime() + 30000),
    audit: { action: "EVENT_FAILED", attemptNumber: 4, actorId: "system", incentiveEventId: ingested.event.id },
  });
  assert(firstFinish.applied === true, "first outcome is stored");
  repo.stored(ingested.event.id).status = "FAILED";
  repo.stored(ingested.event.id).nextAttemptAt = now;
  const secondClaim = await repo.claim(ingested.event.id, { now, workerId: "worker-3" });
  const secondFinish = await repo.finish(ingested.event.id, secondClaim.token, {
    status: "FAILED",
    nextAttemptAt: new Date(now.getTime() + 60000),
    audit: { action: "EVENT_FAILED", attemptNumber: repo.stored(ingested.event.id).attempts, actorId: "system", incentiveEventId: ingested.event.id },
  });
  assert(secondFinish.applied === true, "repeated failure gets its own audit");
  const failedAudits = repo.audits.filter((row) => row.action === "EVENT_FAILED" && row.incentiveEventId === ingested.event.id);
  assert(failedAudits.length === 2, "both failure audits exist");
  assert(new Set(failedAudits.map((row) => row.attemptNumber)).size === 2, "failure audits do not share an attempt number");
}

function testClaimSql() {
  const source = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/events/repository.js"), "utf8");
  const claimSource = source.slice(source.indexOf("async claim("), source.indexOf("async finish("));
  const updateAt = claimSource.indexOf('UPDATE "IncentiveEvent" AS e');
  const existsAt = claimSource.indexOf("AND EXISTS (");
  const readAt = claimSource.indexOf("incentiveSetting.findMany");
  assert(updateAt !== -1 && existsAt > updateAt && readAt > existsAt, "flag read does not run before the claim update");
  assert(claimSource.includes(`s."key" = 'master_enabled'`), "claim SQL names the master key");
  assert(claimSource.includes("btrim(s.\"value\", E' \\\\t\\\\n\\\\r\\\\f\\\\v') = 'true'"), "claim SQL trims the same whitespace as issuance");
  assert(claimSource.includes(`e."attempts" + 1`), "claim SQL increments attempts");
  assert(claimSource.includes(`e."status" IN ('PENDING', 'FAILED')`), "claim SQL keeps the eligible statuses");
  assert(claimSource.includes(`e."nextAttemptAt" IS NULL OR e."nextAttemptAt" <=`), "claim SQL keeps the due check");
  assert(!claimSource.includes("updateMany"), "claim does not use a separate event update");
  assert(!claimSource.includes("$executeRawUnsafe"), "claim SQL is parameterised");
  assert(!source.includes("attempts: 0"), "replay does not reset attempts");
}

function testBoundaries() {
  const migration = fs.readFileSync(
    path.join(__dirname, "../prisma/migrations/20261117183000_incentive_event_processing/migration.sql"),
    "utf8"
  );
  assert(!/\bDROP TABLE\b/i.test(migration), "phase 2C migration does not drop tables");
  assert(!/ALTER TABLE "(User|Order|Listing|Coupon|AppSetting)"/i.test(migration), "phase 2C migration does not alter core tables");
  assert(migration.includes("IncentiveEvent_one_terminal_order_event"), "order terminal index is present");
  assert(migration.includes("claimToken"), "claim token column is present");
  const source = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/events/process.js"), "utf8");
  assert(!source.includes("incentiveReward.create"), "processing does not issue rewards");
  assert(!source.includes("incentiveLedgerEntry.create"), "processing does not write the ledger");
  assert(!source.includes("incentiveReferral.create"), "processing does not create referrals");
  assert(isDue && leaseExpired, "lifecycle helpers stay available");
}

function uniqueError(meta, message) {
  const error = new Error(message || "Unique constraint failed");
  error.code = "P2002";
  error.meta = meta;
  return error;
}

function repositoryFor(rows, createError) {
  return createPrismaEventRepository({
    incentiveEvent: {
      async create() {
        if (createError) throw createError;
        throw new Error("unexpected insert");
      },
      async findUnique({ where }) {
        return rows.find((row) => row.eventId === where.eventId) || null;
      },
      async findFirst({ where }) {
        return rows.find((row) => (
          row.entityType === where.entityType
          && row.entityId === where.entityId
          && where.type.in.includes(row.type)
        )) || null;
      },
    },
  });
}

async function testUniqueViolationMapping() {
  const existing = {
    id: "event-row",
    eventId: "ORDER_QUALIFIED:order-1",
    type: "ORDER_QUALIFIED",
    entityType: "order",
    entityId: "order-1",
    status: "PENDING",
    attempts: 0,
  };
  const terminal = repositoryFor(
    [existing],
    uniqueError(
      { modelName: "IncentiveEvent", target: ["entityId"] },
      "Unique constraint failed on the fields: (`entityId`)"
    )
  );
  await expectError(
    () => ingestEvent(terminal, { type: "ORDER_CANCELLED", entityId: "order-1", occurredAt: "2026-06-01T00:00:00.000Z" }),
    409,
    "ORDER_TERMINAL_CONFLICT"
  );

  const namedIndex = repositoryFor(
    [existing],
    uniqueError({ modelName: "IncentiveEvent", constraint: "IncentiveEvent_one_terminal_order_event", target: ["entityId"] })
  );
  await expectError(
    () => ingestEvent(namedIndex, { type: "ORDER_CANCELLED", entityId: "order-1", occurredAt: "2026-06-01T00:00:00.000Z" }),
    409,
    "ORDER_TERMINAL_CONFLICT"
  );

  const duplicate = repositoryFor(
    [{ id: "user-row", eventId: "USER_REGISTERED:user-1", type: "USER_REGISTERED", entityType: "user", entityId: "user-1" }],
    uniqueError({ modelName: "IncentiveEvent", target: "eventId" }, "Unique constraint failed on the fields: (`eventId`)")
  );
  const replay = await ingestEvent(duplicate, { type: "USER_REGISTERED", entityId: "user-1", occurredAt: "2026-06-01T00:00:00.000Z" });
  assert(replay.created === false && replay.event.id === "user-row", "duplicate eventId stays idempotent");

  const unrelatedError = uniqueError(
    { modelName: "IncentiveAuditLog", target: ["incentiveEventId", "action", "attemptNumber"] },
    "Unique constraint failed on the fields: (`incentiveEventId`, `action`, `attemptNumber`)"
  );
  const unrelated = repositoryFor([], unrelatedError);
  let thrown = null;
  try {
    await ingestEvent(unrelated, { type: "USER_REGISTERED", entityId: "user-2", occurredAt: "2026-06-01T00:00:00.000Z" });
  } catch (error) {
    thrown = error;
  }
  assert(thrown === unrelatedError, "unrelated unique violation keeps the original error");
  assert(thrown.code === "P2002", "unrelated unique violation stays P2002");
  assert(thrown.code !== "ORDER_TERMINAL_CONFLICT", "unrelated unique violation is not a terminal order conflict");
}

async function main() {
  await testValidationAndIdempotency();
  await testUniqueViolationMapping();
  await testQualification();
  await testMasterAndMatching();
  await testRetryFenceAndRecovery();
  await testClaimAndReplayAttempts();
  testClaimSql();
  await testHttpPermissions();
  testBoundaries();
  console.log("incentive events ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
