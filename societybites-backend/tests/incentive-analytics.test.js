process.env.DATABASE_URL = "postgresql://postgres@127.0.0.1:5432/societybites_incentive_unit";
process.env.DIRECT_URL = process.env.DATABASE_URL;

const fs = require("fs");
const http = require("http");
const path = require("path");
const express = require("express");
const { createMemoryRepository } = require("../modules/incentive-engine/campaign/memoryRepository");
const service = require("../modules/incentive-engine/campaign/service");
const { createAdminRouter } = require("../modules/incentive-engine/routes/adminCampaigns");
const { createInsightsRouter } = require("../modules/incentive-engine/routes/adminInsights");
const { requireAdmin, requireSuperAdmin } = require("../middleware/requireAdmin");
const { listEvents } = require("../modules/incentive-engine/events/process");
const {
  shapePerformance,
  shapeReferralAnalytics,
  shapeRewardReport,
  shapeRisk,
  presentLeader,
  qualificationNote,
} = require("../modules/incentive-engine/analytics/report");

function assert(condition, message) {
  if (!condition) throw new Error(message);
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
      {
        hostname: "127.0.0.1",
        port: address.port,
        path: requestPath,
        method,
        headers,
      },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => chunks.push(chunk));
        response.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let json = null;
          try {
            json = text ? JSON.parse(text) : null;
          } catch (error) {
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

async function buildSource() {
  const repository = createMemoryRepository();
  const actorId = "admin-1";
  const created = await service.createCampaign(repository, {
    actorId,
    body: {
      name: "Summer",
      category: "BUYER_ACQUISITION",
      endsAt: "2026-12-31T00:00:00.000Z",
    },
  });
  await service.setAudiences(repository, {
    campaignId: created.id,
    actorId,
    body: { audiences: [{ kind: "BUYERS" }] },
  });
  await service.setTriggers(repository, {
    campaignId: created.id,
    actorId,
    body: { triggers: [{ eventType: "ORDER_QUALIFIED" }] },
  });
  await service.setRules(repository, {
    campaignId: created.id,
    actorId,
    body: {
      eligibility: "RULES",
      rules: {
        combinator: "AND",
        conditions: [
          { field: "event.type", operator: "EQUALS", value: "ORDER_QUALIFIED" },
          {
            combinator: "OR",
            conditions: [{ field: "order.total", operator: "GREATER_THAN", value: 100 }],
          },
        ],
      },
    },
  });
  await service.setBudget(repository, {
    campaignId: created.id,
    actorId,
    body: { amountCap: "100.00", maxRewardCount: 4 },
  });
  await service.setRewards(repository, {
    campaignId: created.id,
    actorId,
    body: {
      rewards: [{ slot: "primary", recipientRole: "REFERRER", rewardType: "FIXED_COUPON", amount: "10" }],
    },
  });
  await service.setReferralPolicy(repository, {
    campaignId: created.id,
    actorId,
    body: {
      referralPolicy: {
        codeExpiresInDays: 30,
        qualificationWindowDays: 14,
        maxAttributionsPerReferrer: 10,
        maxQualifiedPerReferrer: 5,
        buyer: { maxAccountAgeHours: 72 },
      },
    },
  });
  return { repository, created };
}

async function testDuplicate() {
  const { repository, created } = await buildSource();
  const sourceBefore = await service.getCampaign(repository, created.id);
  let sameName = false;
  try {
    await service.duplicateCampaign(repository, { campaignId: created.id, actorId: "admin-1", body: { name: "Summer" } });
  } catch (error) {
    sameName = error.code === "NAME_UNCHANGED";
  }
  assert(sameName, "a copy requires a different name");

  const copy = await service.duplicateCampaign(repository, {
    campaignId: created.id,
    actorId: "admin-1",
    body: { name: "Summer copy" },
  });
  assert(copy.id !== created.id, "duplicate is a new campaign");
  assert(copy.status === "DRAFT", "duplicate starts as a draft");
  assert(copy.version.snapshot.audiences[0].kind === "BUYERS", "audience is copied");
  assert(copy.version.snapshot.triggers[0].eventType === "ORDER_QUALIFIED", "trigger is copied");
  assert(copy.version.snapshot.rules.conditions.length === 2, "nested rules are copied");
  assert(copy.version.snapshot.rewards[0].rewardType === "FIXED_COUPON", "reward definition is copied");
  assert(copy.version.snapshot.referralPolicy.maxQualifiedPerReferrer === 5, "referral policy is copied");
  assert(copy.version.snapshot.budget.issuedAmount === "0.00", "consumed budget is not copied");
  assert(copy.version.snapshot.budget.amountCap === "100.00", "configured budget is copied");
  const sourceAfter = await service.getCampaign(repository, created.id);
  assert(sourceAfter.status === sourceBefore.status, "source status stays unchanged");
  assert(sourceAfter.currentVersionId === sourceBefore.currentVersionId, "source version stays unchanged");
  assert(!copy.version.snapshot.rewards.some((row) => row.status), "a copied reward definition has no issuance status");
}

async function testReports() {
  const now = new Date("2026-11-17T00:00:00.000Z");
  const performance = shapePerformance({
    campaignId: "campaign-1",
    range: { from: "2026-11-01T00:00:00.000Z", to: "2026-11-17T00:00:00.000Z" },
    status: "SCHEDULED",
    startsAt: "2026-12-01T00:00:00.000Z",
    endsAt: "2026-12-20T00:00:00.000Z",
    referrals: { attributed: 4, qualified: 1, pending: 2 },
    rewards: [
      { status: "ISSUED", rewardType: "FIXED_COUPON", count: 1 },
      { status: "PENDING_APPROVAL", rewardType: "POINTS", count: 2 },
      { status: "REJECTED", rewardType: "PROMOTIONAL_CREDIT", count: 1 },
      { status: "EXPIRED", rewardType: "PERCENTAGE_COUPON", count: 1 },
    ],
    pendingApprovalOpen: 2,
    budget: { configured: "100.00", consumed: "100.00" },
    earlierVersionsIssued: "0.00",
    series: [
      { day: "2026-11-02", attributed: 2, qualified: 1, issued: 0 },
      { day: "2026-11-02", attributed: 0, qualified: 0, issued: 1 },
    ],
    timeline: [{ id: "audit-1", action: "CAMPAIGN_PAUSED", actorId: "admin-1", createdAt: now, before: { status: "ACTIVE" }, after: { status: "PAUSED", phone: "999" } }],
  }, now);
  assert(performance.referrals.conversionRate === 25, "conversion uses qualified divided by attributed");
  assert(performance.budget.exhausted === true, "a full budget is exhausted");
  assert(performance.budget.available === "0.00", "available budget is the remainder");
  assert(performance.schedule.scheduledStart === true, "scheduled start is reported from status");
  assert(performance.schedule.remaining.hours > 0, "remaining duration comes from the end date");
  assert(performance.series[0].issued === 1 && performance.series[0].attributed === 2, "daily series merges real counts");
  assert(performance.timeline[0].after.phone == null, "audit timeline drops private fields");
  assert(performance.rewards.byType.FIXED_COUPON.issued === 1, "issued rewards stay split by type");

  const referrals = shapeReferralAnalytics({
    range: {},
    codesGenerated: 3,
    byKind: [
      { acquisitionKind: "BUYER_ACQUISITION", status: "QUALIFIED", count: 1 },
      { acquisitionKind: "SELLER_ACQUISITION", status: "ATTRIBUTED", count: 2 },
    ],
    failureReasons: [
      { reason: "SELF_REFERRAL", count: 2 },
      { reason: "CODE_EXPIRED", count: 1 },
      { reason: "CUSTOM_REVIEW", count: 4 },
    ],
    leaders: [{ displayName: "Asha", qualified: 3, userId: "user-1", phone: "9000000000" }],
    rewardsApproved: 1,
    rewardsIssued: 1,
  }, now);
  assert(referrals.funnel.codesGenerated === 3, "funnel starts from stored codes");
  assert(referrals.funnel.qualified === 1, "qualified count comes from referral rows");
  assert(referrals.comparison.SELLER_ACQUISITION.pending === 2, "seller and buyer counts stay separate");
  assert(referrals.failures.recorded.find((row) => row.reason === "Self-referral").count === 2, "self-referral uses stored rejections");
  assert(referrals.failures.other[0].reason === "CUSTOM_REVIEW", "unknown stored reasons are kept");
  assert(referrals.leaders[0].displayName === "Asha" && referrals.leaders[0].userId == null && referrals.leaders[0].phone == null, "leaderboard keeps the display name only");
  assert(presentLeader({ displayName: "  ", qualified: 1 }).displayName === "Member", "a blank name becomes Member");

  const rewards = shapeRewardReport({
    range: {},
    statuses: [
      { status: "ISSUED", rewardType: "PROMOTIONAL_CREDIT", count: 1 },
      { status: "REDEEMED", rewardType: "POINTS", count: 1 },
      { status: "EXPIRED", rewardType: "FIXED_COUPON", count: 1 },
      { status: "PARTIALLY_REDEEMED", rewardType: "PROMOTIONAL_CREDIT", count: 1 },
      { status: "REJECTED", rewardType: "POINTS", count: 1 },
      { status: "PENDING_APPROVAL", rewardType: "PERCENTAGE_COUPON", count: 1 },
    ],
    balances: { promotionalCredit: "6.00", points: "4.00" },
    budgetExhausted: 1,
    issuedPastExpiry: 0,
    timeline: [],
    expiring: [],
  }, now);
  assert(rewards.counts.PENDING_APPROVAL === 1, "pending approval is its own status");
  assert(rewards.byType.PROMOTIONAL_CREDIT.partiallyRedeemed === 1, "partial redemption is counted");
  assert(rewards.balances.withdrawable === false, "credit and points are not withdrawable");
  assert(rewards.exceptions.budgetExhausted === 1, "budget exhaustion comes from the audit count");

  const risk = shapeRisk({
    failureReasons: [{ reason: "REFERRAL_LIMIT", count: 3 }],
    approachingCap: [{ displayName: "Ravi", userId: "seller-1", attributed: 8, limit: 10 }],
  });
  assert(risk.indicators.every((row) => row.automaticAction === "none"), "risk indicators do not take an automatic action");
  assert(risk.sharedAccountPatterns.detected === false, "shared-account patterns are not invented");
  assert(risk.indicators.find((row) => row.code === "CAP_APPROACHING").reviewRequired === true, "a near cap is marked for review");

  assert(
    qualificationNote({
      status: "ATTRIBUTED",
      acquisitionKind: "SELLER_ACQUISITION",
      sellerEnabledAt: null,
      listingId: null,
      qualifyingOrderId: "order-1",
    }).includes("seller terms"),
    "a seller referral explains the missing milestone"
  );
}

async function testPermissions() {
  const { repository, created } = await buildSource();
  const seen = [];
  const app = express();
  app.use(express.json());
  app.use("/incentive/admin", createAdminRouter({
    repository,
    loadFlags: async () => ({ master: false }),
    requireUser: testUser,
    requireAdmin,
    requireSuperAdmin,
  }));
  app.use("/incentive/admin", createInsightsRouter({
    client: {},
    load: {
      async performance(_client, args) {
        seen.push(args);
        return { campaignId: args.campaignId, ok: true };
      },
      async referralAnalytics() {
        return { funnel: {} };
      },
      async leaderboard() {
        return [{ displayName: "Asha", qualified: 1, userId: "user-1", phone: "9000000000" }];
      },
      async rewardReport() {
        return { counts: {} };
      },
      async auditPage() {
        return { entries: [], nextCursor: null };
      },
      async risk() {
        return { indicators: [] };
      },
    },
    requireUser: testUser,
    requireAdmin,
    requireSuperAdmin,
  }));
  const server = await new Promise((resolve) => {
    const listening = app.listen(0, "127.0.0.1", () => resolve(listening));
  });
  try {
    const denied = await jsonRequest(server, {
      method: "POST",
      requestPath: `/incentive/admin/campaigns/${created.id}/duplicate`,
      role: "buyer",
      consoleAdmin: true,
      body: { name: "Copied by reader" },
    });
    assert(denied.status === 403, "a portal admin cannot duplicate a campaign");
    const copied = await jsonRequest(server, {
      method: "POST",
      requestPath: `/incentive/admin/campaigns/${created.id}/duplicate`,
      role: "super_admin",
      body: { name: "Copied campaign" },
    });
    assert(copied.status === 201 && copied.json.status === "DRAFT", "super admin duplicate stays a draft");
    const buyer = await jsonRequest(server, {
      method: "GET",
      requestPath: `/incentive/admin/campaigns/${created.id}/performance`,
      role: "buyer",
    });
    assert(buyer.status === 403, "a buyer cannot read campaign performance");
    const reader = await jsonRequest(server, {
      method: "GET",
      requestPath: `/incentive/admin/campaigns/${created.id}/performance?from=2026-11-01T00:00:00.000Z`,
      role: "buyer",
      consoleAdmin: true,
    });
    assert(reader.status === 200 && seen[0].campaignId === created.id, "a portal admin can read performance");
    const board = await jsonRequest(server, {
      method: "GET",
      requestPath: "/incentive/admin/referral-leaderboard?userId=someone-else",
      role: "buyer",
      consoleAdmin: true,
    });
    assert(board.status === 200 && board.json.leaders[0].userId === "user-1", "admin leaderboard can identify a referrer");
    assert(board.json.leaders[0].phone == null, "admin leaderboard does not return a phone number");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }

  const page = await listEvents({
    async listEvents() {
      return [
        { id: "event-2", eventId: "b", type: "ORDER_QUALIFIED", status: "FAILED", attempts: 3, lastError: "budget", payload: {}, createdAt: "2026-11-02T00:00:00.000Z" },
        { id: "event-1", eventId: "a", type: "USER_REGISTERED", status: "PENDING", attempts: 0, lastError: null, payload: {}, createdAt: "2026-11-01T00:00:00.000Z" },
      ];
    },
  }, { limit: 1 });
  assert(page.events.length === 1 && page.nextCursor === "event-2", "event monitoring pages the stored rows");
  assert(page.events[0].lastError === "budget" && page.events[0].attempts === 3, "event monitoring keeps the recorded error and attempts");

  const referralsSource = fs.readFileSync(path.join(__dirname, "../modules/incentive-engine/routes/referrals.js"), "utf8");
  assert(referralsSource.includes("delete query.userId"), "caller leaderboard ignores a user id in the query");
  assert(!referralsSource.includes("phone"), "caller referral routes do not select a phone number");
}

async function main() {
  await testDuplicate();
  await testReports();
  await testPermissions();
  console.log("incentive analytics ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
