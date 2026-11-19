/**
 * Phase 3 buyer, seller, campaign, reporting, and permission journey.
 * Not part of npm test. The v2 runner must set DATABASE_URL before Node starts.
 * This file checks that URL before loading application code, so a missing or
 * rejected URL does not load .env. It never applies a migration.
 *
 * Target: 127.0.0.1:5432/societybites_incentive_integration_v2
 * Incentive switches are written only for this process and restored afterwards.
 * Notification delivery is replaced with a no-op before the event processor loads.
 */
const crypto = require("crypto");
const http = require("http");
const { Prisma, PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("../lib/prismaPool");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_integration_v2";
const PREFIX = `p3j${crypto.randomBytes(4).toString("hex")}`;
const LEDGER_TRIGGERS = [
  "incentive_ledger_no_update",
  "incentive_ledger_no_delete",
  "incentive_ledger_guard_insert",
];
const LOCK_A = 872341;
const LOCK_B = 230611;
const FLAG_KEY_LIST = [
  "master_enabled",
  "issuance_enabled",
  "redemption_enabled",
  "referral_enabled",
  "buyer_referral_enabled",
  "seller_referral_enabled",
  "promotional_campaigns_enabled",
];
const FLAGS_ON = {
  master: true,
  issuance: true,
  redemption: true,
  referral: true,
  buyerReferral: true,
  sellerReferral: true,
  promotional: true,
};

function scrub(value) {
  return String(value || "").replace(/postgresql:\/\/\S+/gi, "postgresql://[redacted]");
}

function assertSafeUrl(value) {
  if (!value || typeof value !== "string") {
    throw new Error("DATABASE_URL must be set by the v2 runner before this test starts");
  }
  const lowered = value.toLowerCase();
  if (lowered.includes("supabase") || lowered.includes("pooler.supabase")) {
    throw new Error("DATABASE_URL must not point at Supabase");
  }
  let parsed;
  try {
    parsed = new URL(value);
  } catch (error) {
    throw new Error("DATABASE_URL is not a valid URL");
  }
  const database = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  if (parsed.hostname !== REQUIRED_HOST) throw new Error(`host must be ${REQUIRED_HOST}`);
  if (parsed.port !== REQUIRED_PORT) throw new Error(`port must be ${REQUIRED_PORT}`);
  if (database !== REQUIRED_DATABASE) throw new Error(`database must be ${REQUIRED_DATABASE}`);
  for (const key of parsed.searchParams.keys()) {
    if (key !== "connection_limit") throw new Error("DATABASE_URL has an unexpected parameter");
  }
}

function localClient(url) {
  const bounded = new URL(withPrismaPoolParams(url));
  bounded.searchParams.set("connection_limit", "5");
  return new PrismaClient({ datasources: { db: { url: bounded.toString() } } });
}

assertSafeUrl(process.env.DATABASE_URL);

const notifications = require("../utils/notifications");
notifications.notifyIncentiveReward = async () => {};

const { FLAG_KEYS } = require("../modules/incentive-engine/configuration/flags");
const { createPrismaRepository } = require("../modules/incentive-engine/campaign/prismaRepository");
const campaignService = require("../modules/incentive-engine/campaign/service");
const { createPrismaReferralRepository } = require("../modules/incentive-engine/routes/referrals");
const { createReferralCode, listReferralCodes } = require("../modules/incentive-engine/referrals/codes");
const { createPrismaReferralDb } = require("../modules/incentive-engine/referrals/attribute");
const { createPrismaEventRepository } = require("../modules/incentive-engine/events/repository");
const { evaluateClaimed, replayEvent } = require("../modules/incentive-engine/events/process");
const {
  emitOrderQualifiedIfReady,
  recordListingPublished,
  recordSellerBecameSeller,
} = require("../modules/incentive-engine/events/productHooks");
const { validatePayload } = require("../modules/incentive-engine/events/validate");
const { auditPage, referralAnalytics, rewardReport, risk } = require("../modules/incentive-engine/analytics/query");
const { listOwnRewards } = require("../modules/incentive-engine/rewards/read");
const { createRewardsRouter } = require("../modules/incentive-engine/routes/adminRewards");
const { createMyRewardsRouter } = require("../modules/incentive-engine/routes/myRewards");
const { signToken } = require("../lib/jwt");
const express = require("express");

const results = [];
const owned = {
  userIds: [],
  societyIds: [],
  listingIds: [],
  orderIds: [],
  campaignIds: [],
  entityIds: [],
  couponIds: [],
};

function record(id, name, expected, status, actual) {
  results.push({ id, name, expected, status, actual: scrub(actual).slice(0, 700) });
  console.log(`${status} ${id} ${name} expected=${expected} actual=${scrub(actual).slice(0, 300)}`);
}

async function check(id, name, expected, work) {
  try {
    const actual = await work();
    if (actual && typeof actual === "object" && Object.prototype.hasOwnProperty.call(actual, "ok")) {
      record(id, name, expected, actual.ok ? "PASS" : "FAIL", actual.actual);
      return actual.ok;
    }
    const ok = actual === true;
    record(id, name, expected, ok ? "PASS" : "FAIL", ok ? "matched" : JSON.stringify(actual));
    return ok;
  } catch (error) {
    record(id, name, expected, "FAIL", `${error && error.code ? error.code + " " : ""}${error && error.stack ? error.stack : error}`);
    return false;
  }
}

async function expectCode(work, code) {
  try {
    await work();
    return { ok: false, actual: "no error" };
  } catch (error) {
    return { ok: error.code === code, actual: error.code || error.message };
  }
}

async function tableCounts(prisma) {
  const tables = [
    "User", "Society", "Listing", "Order", "Coupon", "CouponEligibleUser",
    "IncentiveCampaign", "IncentiveReward", "IncentiveEvent", "IncentiveReferral",
    "IncentiveLedgerEntry", "IncentiveSetting", "IncentiveAuditLog", "AppSetting",
  ];
  const counts = {};
  for (const table of tables) {
    const rows = await prisma.$queryRawUnsafe(`SELECT COUNT(*)::int AS n FROM "${table}"`);
    counts[table] = rows[0].n;
  }
  return counts;
}

async function triggerStates(prisma) {
  const triggers = await prisma.$queryRaw`
    SELECT tgname, tgenabled::text AS state
    FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgrelid = '"IncentiveLedgerEntry"'::regclass
      AND tgname IN ('incentive_ledger_no_update', 'incentive_ledger_no_delete', 'incentive_ledger_guard_insert')
  `;
  return Object.fromEntries(triggers.map((row) => [row.tgname, row.state]));
}

function later(seconds) {
  return new Date(Date.now() + seconds * 1000);
}

async function main() {
  const prisma = localClient(process.env.DATABASE_URL);
  const campaigns = createPrismaRepository(prisma);
  const codeRepository = createPrismaReferralRepository(prisma);
  const referrals = createPrismaReferralDb(prisma);
  const events = createPrismaEventRepository(prisma);
  const actorId = "phase3-journey";
  let phone = 7000000000 + crypto.randomInt(0, 200000);
  const nextPhone = () => `+91${phone++}`;
  let originalSettings = [];
  let beforeCounts = null;
  let server = null;
  const created = { campaigns: {} };

  function userView(row) {
    return { id: row.id, role: row.role, createdAt: row.createdAt, phone: row.phone, name: row.name };
  }

  async function makeUser(role, extra = {}) {
    const row = await prisma.user.create({
      data: {
        phone: nextPhone(),
        name: `${PREFIX} ${role}`,
        role,
        societyId: extra.societyId,
        consoleAdmin: extra.consoleAdmin === true,
      },
    });
    owned.userIds.push(row.id);
    return row;
  }

  async function makeListing(seller, when, status = "active") {
    const row = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `${PREFIX} thali`,
        price: 120,
        quantity: 5,
        status,
        firstPublishedAt: status === "draft" ? null : when,
        foodType: "VEG",
      },
    });
    owned.listingIds.push(row.id);
    owned.entityIds.push(row.id);
    return row;
  }

  async function makeOrder({ buyer, seller, listing, status, when }) {
    const row = await prisma.order.create({
      data: {
        orderNumber: `${PREFIX}-${crypto.randomBytes(3).toString("hex")}`,
        buyerId: buyer.id,
        societyId: buyer.societyId,
        status,
        paymentMethod: "cash",
        paymentStatus: status === "completed" ? "paid" : "pending",
        paymentProvider: "direct_upi",
        subtotal: 120,
        total: 120,
        completedAt: status === "completed" ? when : null,
        sellerConfirmedPaidAt: status === "completed" ? when : null,
        items: { create: [{ listingId: listing.id, quantity: 1, unitPrice: 120 }] },
      },
    });
    owned.orderIds.push(row.id);
    owned.entityIds.push(row.id);
    return row;
  }

  async function settle(eventId) {
    const row = await prisma.incentiveEvent.findUnique({ where: { eventId } });
    if (!row) throw new Error(`event ${eventId} was not stored`);
    owned.entityIds.push(row.entityId);
    if (row.status === "PROCESSED" || row.status === "SKIPPED") return row;
    const claim = await events.claim(row.id, { now: new Date(), workerId: "phase3-journey" });
    if (!claim.claimed) throw new Error(`event ${eventId} was not claimed`);
    await evaluateClaimed(events, claim.event, {
      token: claim.token,
      flags: claim.flags,
      now: new Date(),
      actorId: "system",
      loadOrder: (id) => events.loadOrder(id),
    });
    return prisma.incentiveEvent.findUnique({ where: { id: row.id } });
  }

  async function openCampaign(body) {
    const saved = await campaignService.createCampaign(campaigns, { actorId, body });
    owned.campaignIds.push(saved.id);
    return saved;
  }

  async function configure(id, { audience, trigger, reward, policy, budget, rules }) {
    await campaignService.setAudiences(campaigns, {
      campaignId: id, actorId, body: { audiences: [{ kind: audience }] },
    });
    await campaignService.setTriggers(campaigns, {
      campaignId: id, actorId, body: { triggers: [{ eventType: trigger }] },
    });
    await campaignService.setBudget(campaigns, { campaignId: id, actorId, body: budget });
    await campaignService.setRewards(campaigns, { campaignId: id, actorId, body: { rewards: [reward] } });
    if (rules) {
      await campaignService.setRules(campaigns, { campaignId: id, actorId, body: rules });
    } else {
      await campaignService.setRules(campaigns, {
        campaignId: id, actorId, body: { eligibility: "AUDIENCE_AND_TRIGGER_ONLY" },
      });
    }
    if (policy) {
      await campaignService.setReferralPolicy(campaigns, {
        campaignId: id, actorId, body: { referralPolicy: policy },
      });
    }
  }

  const buyerPolicy = (caps = {}) => ({
    codeExpiresInDays: 30,
    qualificationWindowDays: 30,
    maxAttributionsPerReferrer: caps.attributions == null ? 10 : caps.attributions,
    maxQualifiedPerReferrer: caps.qualified == null ? 5 : caps.qualified,
    requireAdminApproval: false,
    buyer: { maxAccountAgeHours: 720 },
  });
  const sellerPolicy = {
    codeExpiresInDays: 30,
    qualificationWindowDays: 30,
    maxAttributionsPerReferrer: 10,
    maxQualifiedPerReferrer: 5,
    requireAdminApproval: false,
    seller: { maxAccountAgeHours: 720 },
  };
  const couponReward = (approval) => ({
    slot: "referrer",
    recipientRole: "REFERRER",
    rewardType: "FIXED_COUPON",
    amount: "40.00",
    expiryDays: 14,
    requireAdminApproval: approval,
  });

  try {
    const identity = await prisma.$queryRaw`SELECT current_database() AS db, inet_server_addr()::text AS host, inet_server_port()::int AS port`;
    if (identity[0].db !== REQUIRED_DATABASE || !String(identity[0].host).includes("127.0.0.1") || identity[0].port !== 5432) {
      throw new Error("Connected database is not the approved local database");
    }
    const locked = await prisma.$queryRaw`SELECT pg_try_advisory_lock(${LOCK_A}::int, ${LOCK_B}::int) AS ok`;
    if (!locked[0].ok) throw new Error("Another incentive PostgreSQL harness holds the session lock");
    const triggers = await triggerStates(prisma);
    if (!LEDGER_TRIGGERS.every((name) => triggers[name] === "O")) {
      throw new Error("Ledger triggers are missing or disabled");
    }
    originalSettings = await prisma.incentiveSetting.findMany();
    if (originalSettings.some((row) => String(row.value).replace(/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/g, "") === "true")) {
      throw new Error("An incentive switch is already enabled");
    }
    beforeCounts = await tableCounts(prisma);
    console.log(`BEFORE_COUNTS ${JSON.stringify(beforeCounts)}`);

    for (const key of FLAG_KEY_LIST) {
      await prisma.incentiveSetting.upsert({
        where: { key },
        update: { value: "true" },
        create: { key, value: "true" },
      });
    }

    const society = await prisma.society.create({
      data: { name: `${PREFIX} society`, city: "Bengaluru", inviteCode: PREFIX.slice(0, 16).toUpperCase() },
    });
    owned.societyIds.push(society.id);
    const superAdmin = await makeUser("super_admin", { societyId: society.id });
    const portal = await makeUser("buyer", { societyId: society.id, consoleAdmin: true });
    const buyerA = await makeUser("buyer", { societyId: society.id });
    const buyerB = await makeUser("buyer", { societyId: society.id });
    const buyerC = await makeUser("buyer", { societyId: society.id });
    const buyerPrior = await makeUser("buyer", { societyId: society.id });
    const buyerExpired = await makeUser("buyer", { societyId: society.id });
    const buyerCapOne = await makeUser("buyer", { societyId: society.id });
    const buyerCapTwo = await makeUser("buyer", { societyId: society.id });
    const buyerSelf = buyerA;
    const sellerA = await makeUser("seller", { societyId: society.id });
    const sellerB = await makeUser("seller", { societyId: society.id });
    const sellerOrdered = await makeUser("seller", { societyId: society.id });
    const sellerListed = await makeUser("seller", { societyId: society.id });
    const customer = await makeUser("buyer", { societyId: society.id });
    const kitchen = await makeUser("seller", { societyId: society.id });

    const endsAt = new Date(Date.now() + 20 * 24 * 60 * 60 * 1000).toISOString();
    const buyerCampaign = await openCampaign({
      name: `${PREFIX} buyer`, category: "BUYER_ACQUISITION", endsAt,
    });
    const sellerCampaign = await openCampaign({
      name: `${PREFIX} seller`, category: "SELLER_ACQUISITION", endsAt,
    });
    const capCampaign = await openCampaign({
      name: `${PREFIX} cap`, category: "BUYER_ACQUISITION", endsAt,
    });
    const promo = await openCampaign({
      name: `${PREFIX} promo`, category: "PROMOTIONAL", endsAt,
    });
    const scheduled = await openCampaign({
      name: `${PREFIX} scheduled`,
      category: "PROMOTIONAL",
      startsAt: new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString(),
      endsAt: new Date(Date.now() + 12 * 24 * 60 * 60 * 1000).toISOString(),
    });
    const expired = await openCampaign({
      name: `${PREFIX} expired`,
      category: "PROMOTIONAL",
      startsAt: new Date(Date.now() - 5 * 24 * 60 * 60 * 1000).toISOString(),
      endsAt: new Date(Date.now() - 60 * 1000).toISOString(),
    });
    created.campaigns = { buyerCampaign, sellerCampaign, capCampaign, promo, scheduled, expired };

    await configure(buyerCampaign.id, {
      audience: "BUYERS",
      trigger: "ORDER_QUALIFIED",
      reward: couponReward(false),
      policy: buyerPolicy({ qualified: 2 }),
      budget: { amountCap: "500.00", maxRewardCount: 1 },
    });
    await configure(sellerCampaign.id, {
      audience: "SELLERS",
      trigger: "ORDER_QUALIFIED",
      reward: couponReward(true),
      policy: sellerPolicy,
      budget: { amountCap: "500.00", maxRewardCount: 1 },
    });
    await configure(capCampaign.id, {
      audience: "BUYERS",
      trigger: "ORDER_QUALIFIED",
      reward: couponReward(false),
      policy: buyerPolicy({ attributions: 1, qualified: 1 }),
      budget: { amountCap: "100.00" },
    });

    await check("D01", "Draft campaign accepts a nested AND/OR rule", "rules stored", async () => {
      const saved = await campaignService.setRules(campaigns, {
        campaignId: promo.id,
        actorId,
        body: {
          eligibility: "RULES",
          rules: {
            combinator: "AND",
            conditions: [
              {
                combinator: "OR",
                conditions: [
                  { field: "order.total", operator: "GREATER_THAN_OR_EQUAL", value: 50 },
                  { field: "order.itemCount", operator: "EQUALS", value: 1 },
                ],
              },
              { field: "user.role", operator: "EQUALS", value: "buyer" },
            ],
          },
        },
      });
      const tree = saved.version.snapshot.rules;
      return tree && tree.combinator === "AND" && tree.conditions[0].combinator === "OR";
    });
    await check("D02", "Percentage coupon definition is stored", "PERCENTAGE_COUPON", async () => {
      const saved = await campaignService.setRewards(campaigns, {
        campaignId: promo.id,
        actorId,
        body: { rewards: [{ slot: "percent", recipientRole: "BUYER", rewardType: "PERCENTAGE_COUPON", amount: "10.00", maxDiscount: "25.00" }] },
      });
      return saved.version.snapshot.rewards[0].rewardType === "PERCENTAGE_COUPON";
    });
    await check("D03", "Promotional credit definition is stored", "PROMOTIONAL_CREDIT", async () => {
      const saved = await campaignService.setRewards(campaigns, {
        campaignId: promo.id,
        actorId,
        body: { rewards: [{ slot: "credit", recipientRole: "BUYER", rewardType: "PROMOTIONAL_CREDIT", amount: "15.00" }] },
      });
      return saved.version.snapshot.rewards[0].rewardType === "PROMOTIONAL_CREDIT";
    });
    await check("D04", "Points definition is stored", "POINTS", async () => {
      await campaignService.setAudiences(campaigns, { campaignId: promo.id, actorId, body: { audiences: [{ kind: "BUYERS" }] } });
      await campaignService.setTriggers(campaigns, { campaignId: promo.id, actorId, body: { triggers: [{ eventType: "REVIEW_SUBMITTED" }] } });
      await campaignService.setBudget(campaigns, { campaignId: promo.id, actorId, body: { amountCap: "100.00" } });
      const saved = await campaignService.setRewards(campaigns, {
        campaignId: promo.id,
        actorId,
        body: { rewards: [{ slot: "points", recipientRole: "BUYER", rewardType: "POINTS", amount: "20.00" }] },
      });
      return saved.version.snapshot.rewards[0].rewardType === "POINTS";
    });
    await check("D05", "Arbitrary SQL is rejected by the rule validator", "rejected", () => expectCode(
      () => campaignService.setRules(campaigns, {
        campaignId: promo.id,
        actorId,
        body: { eligibility: "RULES", rules: { field: "order.total; DROP TABLE users", operator: "EQUALS", value: 1 } },
      }),
      "FIELD_INVALID",
    ).then((result) => ({ ok: result.actual !== "no error", actual: result.actual })));
    await check("D06", "Event payload rejects a script field", "rejected", async () => {
      try {
        validatePayload({ script: "process.exit(1)" });
        return { ok: false, actual: "accepted" };
      } catch (error) {
        return { ok: error.statusCode === 400, actual: error.code || error.message };
      }
    });

    await check("D07", "Buyer referral campaign publishes", "ACTIVE", async () => {
      const saved = await campaignService.changeStatus(campaigns, {
        campaignId: buyerCampaign.id, actorId, to: "ACTIVATE", flags: FLAGS_ON,
      });
      return saved.status === "ACTIVE" && Boolean(saved.version.publishedAt);
    });
    await check("D08", "Seller referral campaign publishes", "ACTIVE", async () => {
      const saved = await campaignService.changeStatus(campaigns, {
        campaignId: sellerCampaign.id, actorId, to: "ACTIVATE", flags: FLAGS_ON,
      });
      return saved.status === "ACTIVE";
    });
    await campaignService.changeStatus(campaigns, { campaignId: sellerCampaign.id, actorId, to: "PAUSED", flags: FLAGS_ON });
    await check("D09", "Cap campaign publishes", "ACTIVE", async () => {
      const saved = await campaignService.changeStatus(campaigns, {
        campaignId: capCampaign.id, actorId, to: "ACTIVATE", flags: FLAGS_ON,
      });
      return saved.status === "ACTIVE";
    });

    const codeA = await createReferralCode(codeRepository, {
      user: userView(buyerA), body: { audience: "BUYER", campaignId: buyerCampaign.id },
    });
    await check("B01", "Buyer A receives a referral code", "code", async () => Boolean(codeA.code && codeA.code.code));
    const claimed = await referrals.claim({
      user: userView(buyerB),
      body: { code: codeA.code.code, acquisitionKind: "BUYER_ACQUISITION" },
    });
    await check("B02", "Buyer B is attributed to Buyer A", "ATTRIBUTED", async () => {
      return claimed.created === true && claimed.referral.referrerUserId === buyerA.id && claimed.referral.status === "ATTRIBUTED";
    });
    await check("B03", "Duplicate attribution does not create a second referral", "created false", async () => {
      const again = await referrals.claim({
        user: userView(buyerB),
        body: { code: codeA.code.code, acquisitionKind: "BUYER_ACQUISITION" },
      });
      const count = await prisma.incentiveReferral.count({ where: { referredUserId: buyerB.id } });
      return { ok: again.created === false && count === 1, actual: `created=${again.created} count=${count}` };
    });
    await check("B04", "Self-referral is rejected", "SELF_REFERRAL", () => expectCode(
      () => referrals.claim({ user: userView(buyerSelf), body: { code: codeA.code.code, acquisitionKind: "BUYER_ACQUISITION" } }),
      "SELF_REFERRAL",
    ));
    const priorListing = await makeListing(kitchen, later(0));
    const priorWhen = later(1);
    await makeOrder({ buyer: buyerPrior, seller: kitchen, listing: priorListing, status: "completed", when: priorWhen });
    await check("B05", "A buyer with a qualifying order cannot be attributed", "PRIOR_ACTIVITY", () => expectCode(
      () => referrals.claim({ user: userView(buyerPrior), body: { code: codeA.code.code, acquisitionKind: "BUYER_ACQUISITION" } }),
      "PRIOR_ACTIVITY",
    ));
    const expiring = await createReferralCode(codeRepository, {
      user: userView(buyerC), body: { audience: "BUYER", campaignId: buyerCampaign.id },
    });
    await prisma.incentiveReferralCode.update({
      where: { code: expiring.code.code },
      data: { expiresAt: new Date(Date.now() - 60 * 1000) },
    });
    await check("B06", "An expired referral code is rejected", "CODE_EXPIRED", () => expectCode(
      () => referrals.claim({ user: userView(buyerExpired), body: { code: expiring.code.code, acquisitionKind: "BUYER_ACQUISITION" } }),
      "CODE_EXPIRED",
    ));
    const capCode = await createReferralCode(codeRepository, {
      user: userView(buyerA), body: { audience: "BUYER", campaignId: capCampaign.id },
    });
    await referrals.claim({
      user: userView(buyerCapOne),
      body: { code: capCode.code.code, acquisitionKind: "BUYER_ACQUISITION" },
    });
    await check("B07", "Referral attribution cap is enforced", "REFERRAL_LIMIT", () => expectCode(
      () => referrals.claim({
        user: userView(buyerCapTwo),
        body: { code: capCode.code.code, acquisitionKind: "BUYER_ACQUISITION" },
      }),
      "REFERRAL_LIMIT",
    ));
    await campaignService.changeStatus(campaigns, { campaignId: capCampaign.id, actorId, to: "PAUSED", flags: FLAGS_ON });
    await check("B08", "A paused campaign does not accept a referral", "CAMPAIGN_NOT_ISSUABLE", () => expectCode(
      () => referrals.claim({
        user: userView(buyerCapTwo),
        body: { code: capCode.code.code, acquisitionKind: "BUYER_ACQUISITION" },
      }),
      "CAMPAIGN_NOT_ISSUABLE",
    ));

    const buyerListing = await makeListing(kitchen, later(0));
    const cancelled = await makeOrder({ buyer: buyerB, seller: kitchen, listing: buyerListing, status: "cancelled", when: later(2) });
    await check("B09", "A cancelled order does not qualify the referral", "unqualified", async () => {
      const emitted = await emitOrderQualifiedIfReady(prisma, cancelled.id);
      const forced = await events.insertEvent({
        eventId: `ORDER_QUALIFIED:${cancelled.id}`,
        schemaVersion: 1,
        type: "ORDER_QUALIFIED",
        entityType: "order",
        entityId: cancelled.id,
        userId: buyerB.id,
        occurredAt: later(2),
        payload: {},
        status: "PENDING",
        attempts: 0,
      }).catch(async (error) => {
        if (error && error.code === "P2002") return events.findByEventId(`ORDER_QUALIFIED:${cancelled.id}`);
        throw error;
      });
      const eventId = forced.eventId || `ORDER_QUALIFIED:${cancelled.id}`;
      await settle(eventId);
      const referral = await prisma.incentiveReferral.findUnique({
        where: { referredUserId_acquisitionKind: { referredUserId: buyerB.id, acquisitionKind: "BUYER_ACQUISITION" } },
      });
      return {
        ok: emitted.recorded === false && referral.status === "ATTRIBUTED" && !referral.qualifyingOrderId,
        actual: `recorded=${emitted.recorded} status=${referral.status}`,
      };
    });
    const rejected = await makeOrder({ buyer: buyerB, seller: kitchen, listing: buyerListing, status: "rejected", when: later(3) });
    await check("B10", "A rejected order does not qualify the referral", "unqualified", async () => {
      const emitted = await emitOrderQualifiedIfReady(prisma, rejected.id);
      const referral = await prisma.incentiveReferral.findUnique({
        where: { referredUserId_acquisitionKind: { referredUserId: buyerB.id, acquisitionKind: "BUYER_ACQUISITION" } },
      });
      return { ok: emitted.recorded === false && !referral.qualifyingOrderId, actual: emitted.reason || "recorded" };
    });

    const qualifiedWhen = later(5);
    const qualifiedOrder = await makeOrder({
      buyer: buyerB, seller: kitchen, listing: buyerListing, status: "completed", when: qualifiedWhen,
    });
    await check("B11", "Buyer B's completed order qualifies the referral and issues one coupon", "QUALIFIED coupon", async () => {
      const first = await emitOrderQualifiedIfReady(prisma, qualifiedOrder.id);
      const second = await emitOrderQualifiedIfReady(prisma, qualifiedOrder.id);
      await settle(first.event.eventId);
      const referral = await prisma.incentiveReferral.findUnique({
        where: { referredUserId_acquisitionKind: { referredUserId: buyerB.id, acquisitionKind: "BUYER_ACQUISITION" } },
      });
      const rewards = await prisma.incentiveReward.findMany({ where: { recipientUserId: buyerA.id } });
      const coupon = rewards[0] && rewards[0].couponId
        ? await prisma.coupon.findUnique({ where: { id: rewards[0].couponId } })
        : null;
      if (coupon) owned.couponIds.push(coupon.id);
      const eligible = coupon
        ? await prisma.couponEligibleUser.findMany({ where: { couponId: coupon.id, userId: buyerA.id } })
        : [];
      return {
        ok: second.created === false
          && referral.status === "QUALIFIED"
          && referral.qualifyingOrderId === qualifiedOrder.id
          && rewards.length === 1
          && rewards[0].status === "ISSUED"
          && Boolean(coupon)
          && eligible.length === 1,
        actual: `referral=${referral.status} rewards=${rewards.length} coupon=${Boolean(coupon)} eligible=${eligible.length}`,
      };
    });
    await check("B12", "Replaying a processed event is rejected", "REPLAY_NOT_ALLOWED", async () => {
      const row = await prisma.incentiveEvent.findUnique({ where: { eventId: `ORDER_QUALIFIED:${qualifiedOrder.id}` } });
      return expectCode(() => replayEvent(events, { id: row.id, actorId: superAdmin.id }), "REPLAY_NOT_ALLOWED");
    });

    const secondWhen = later(8);
    const secondOrder = await makeOrder({
      buyer: buyerC, seller: kitchen, listing: buyerListing, status: "completed", when: secondWhen,
    });
    await referrals.claim({
      user: userView(buyerC),
      body: { code: codeA.code.code, acquisitionKind: "BUYER_ACQUISITION" },
    }).catch((error) => {
      if (error.code !== "CODE_EXPIRED") throw error;
    });
    await check("B13", "A second qualified referral does not pass the reward count", "one reward", async () => {
      const freshCode = await prisma.incentiveReferralCode.findUnique({ where: { code: codeA.code.code } });
      if (freshCode.expiresAt && new Date(freshCode.expiresAt) <= new Date()) {
        return { ok: false, actual: "buyer code was expired by the negative test" };
      }
      const existing = await prisma.incentiveReferral.findUnique({
        where: { referredUserId_acquisitionKind: { referredUserId: buyerC.id, acquisitionKind: "BUYER_ACQUISITION" } },
      });
      if (!existing) {
        await referrals.claim({
          user: userView(buyerC),
          body: { code: codeA.code.code, acquisitionKind: "BUYER_ACQUISITION" },
        });
      }
      const emitted = await emitOrderQualifiedIfReady(prisma, secondOrder.id);
      await settle(emitted.event.eventId);
      const referral = await prisma.incentiveReferral.findUnique({
        where: { referredUserId_acquisitionKind: { referredUserId: buyerC.id, acquisitionKind: "BUYER_ACQUISITION" } },
      });
      const rewards = await prisma.incentiveReward.count({ where: { recipientUserId: buyerA.id } });
      return {
        ok: referral.status === "QUALIFIED" && rewards === 1,
        actual: `status=${referral.status} rewards=${rewards}`,
      };
    });

    const capBuyer = await makeUser("buyer", { societyId: society.id });
    await check("B14", "Qualified-referral cap does not issue a reward", "ATTRIBUTED", async () => {
      const attributed = await referrals.claim({
        user: userView(capBuyer),
        body: { code: codeA.code.code, acquisitionKind: "BUYER_ACQUISITION" },
      });
      const when = later(12);
      const order = await makeOrder({ buyer: capBuyer, seller: kitchen, listing: buyerListing, status: "completed", when });
      const emitted = await emitOrderQualifiedIfReady(prisma, order.id);
      await settle(emitted.event.eventId);
      const referral = await prisma.incentiveReferral.findUnique({ where: { id: attributed.referral.id } });
      const rewards = await prisma.incentiveReward.count({ where: { recipientUserId: buyerA.id } });
      const skipped = await prisma.incentiveAuditLog.count({
        where: { campaignId: buyerCampaign.id, action: "REFERRAL_QUALIFICATION_SKIPPED" },
      });
      return {
        ok: referral.status === "ATTRIBUTED" && !referral.qualifyingOrderId === false
          ? referral.status === "ATTRIBUTED" && rewards === 1 && skipped >= 1
          : referral.status === "ATTRIBUTED" && rewards === 1 && skipped >= 1,
        actual: `status=${referral.status} order=${referral.qualifyingOrderId || "none"} rewards=${rewards} skipped=${skipped}`,
      };
    });

    await check("S01", "Seller A receives a referral code", "code", async () => {
      await campaignService.changeStatus(campaigns, { campaignId: buyerCampaign.id, actorId, to: "PAUSED", flags: FLAGS_ON });
      await campaignService.changeStatus(campaigns, { campaignId: sellerCampaign.id, actorId, to: "ACTIVATE", flags: FLAGS_ON });
      const code = await createReferralCode(codeRepository, {
        user: userView(sellerA), body: { audience: "SELLER", campaignId: sellerCampaign.id },
      });
      created.sellerCode = code.code.code;
      return Boolean(created.sellerCode);
    });
    await check("S02", "Seller B is attributed to Seller A", "ATTRIBUTED", async () => {
      const claimedSeller = await referrals.claim({
        user: userView(sellerB),
        body: { code: created.sellerCode, acquisitionKind: "SELLER_ACQUISITION" },
      });
      created.sellerReferralId = claimedSeller.referral.id;
      return claimedSeller.created === true && claimedSeller.referral.status === "ATTRIBUTED";
    });
    await check("S03", "Listing before terms does not qualify the seller", "ATTRIBUTED", async () => {
      const when = later(2);
      const listing = await makeListing(sellerB, when);
      created.sellerListing = listing;
      const recorded = await recordListingPublished(prisma, listing);
      await settle(recorded.event.eventId);
      const referral = await prisma.incentiveReferral.findUnique({ where: { id: created.sellerReferralId } });
      const stored = await prisma.listing.findUnique({ where: { id: listing.id } });
      return {
        ok: referral.status === "ATTRIBUTED"
          && referral.listingPublishedAt
          && !referral.sellerEnabledAt
          && stored.firstPublishedAt,
        actual: `status=${referral.status} listing=${Boolean(referral.listingPublishedAt)} terms=${Boolean(referral.sellerEnabledAt)}`,
      };
    });
    await check("S04", "Duplicate listing publication keeps the first timestamp", "same timestamp", async () => {
      const before = await prisma.incentiveReferral.findUnique({ where: { id: created.sellerReferralId } });
      const again = await recordListingPublished(prisma, created.sellerListing);
      const after = await prisma.incentiveReferral.findUnique({ where: { id: created.sellerReferralId } });
      return {
        ok: again.created === false && new Date(before.listingPublishedAt).getTime() === new Date(after.listingPublishedAt).getTime(),
        actual: `created=${again.created}`,
      };
    });
    await check("S05", "Terms after listing still wait for a qualifying sale", "ATTRIBUTED", async () => {
      const when = later(4);
      await prisma.sellerTermsAcceptance.create({
        data: { userId: sellerB.id, termsVersion: PREFIX, acceptedAt: when },
      });
      const recorded = await recordSellerBecameSeller(prisma, { userId: sellerB.id, occurredAt: when });
      await settle(recorded.event.eventId);
      const referral = await prisma.incentiveReferral.findUnique({ where: { id: created.sellerReferralId } });
      return {
        ok: referral.status === "ATTRIBUTED" && referral.sellerEnabledAt && referral.listingPublishedAt && !referral.qualifyingOrderAt,
        actual: referral.status,
      };
    });
    await check("S06", "A cancelled seller sale does not qualify the referral", "ATTRIBUTED", async () => {
      const order = await makeOrder({
        buyer: customer, seller: sellerB, listing: created.sellerListing, status: "cancelled", when: later(5),
      });
      const emitted = await emitOrderQualifiedIfReady(prisma, order.id);
      const referral = await prisma.incentiveReferral.findUnique({ where: { id: created.sellerReferralId } });
      return { ok: emitted.recorded === false && referral.status === "ATTRIBUTED", actual: referral.status };
    });
    await check("S07", "Seller sale qualifies the referral", "QUALIFIED", async () => {
      const order = await makeOrder({
        buyer: customer, seller: sellerB, listing: created.sellerListing, status: "completed", when: later(8),
      });
      created.sellerOrder = order;
      const emitted = await emitOrderQualifiedIfReady(prisma, order.id);
      await settle(emitted.event.eventId);
      const again = await emitOrderQualifiedIfReady(prisma, order.id);
      const referral = await prisma.incentiveReferral.findUnique({ where: { id: created.sellerReferralId } });
      return {
        ok: again.created === false && referral.status === "QUALIFIED" && referral.qualifyingOrderId === order.id,
        actual: `status=${referral.status} duplicate=${again.created}`,
      };
    });
    await check("S08", "Seller referrer reward follows the production order event", "reward for referrer", async () => {
      const rewards = await prisma.incentiveReward.findMany({
        where: { recipientUserId: { in: [sellerA.id, sellerB.id, customer.id] } },
      });
      const referrer = rewards.find((row) => row.recipientUserId === sellerA.id);
      created.sellerReward = referrer || null;
      return {
        ok: Boolean(referrer),
        actual: rewards.map((row) => `${row.recipientUserId === sellerA.id ? "referrer" : "other"}:${row.status}`).join(",") || "none",
      };
    });
    await check("S09", "Pending seller reward can be approved into a coupon", "ISSUED", async () => {
      if (!created.sellerReward) return { ok: false, actual: "no seller referrer reward" };
      if (created.sellerReward.status !== "PENDING_APPROVAL") {
        return { ok: false, actual: created.sellerReward.status };
      }
      const { approveReward } = require("../modules/incentive-engine/rewards/approve");
      const issued = await prisma.$transaction((tx) => approveReward(tx, {
        rewardId: created.sellerReward.id,
        actorId: superAdmin.id,
      }));
      if (issued.couponId) owned.couponIds.push(issued.couponId);
      const eligible = issued.couponId
        ? await prisma.couponEligibleUser.count({ where: { couponId: issued.couponId, userId: sellerA.id } })
        : 0;
      return { ok: issued.status === "ISSUED" && eligible === 1, actual: `${issued.status} eligible=${eligible}` };
    });

    const orderedListing = await makeListing(sellerOrdered, later(0), "draft");
    await makeOrder({
      buyer: customer, seller: sellerOrdered, listing: orderedListing, status: "completed", when: later(1),
    });
    await check("S10", "A seller with a qualifying sale cannot be attributed", "PRIOR_ACTIVITY", () => expectCode(
      () => referrals.claim({
        user: userView(sellerOrdered),
        body: { code: created.sellerCode, acquisitionKind: "SELLER_ACQUISITION" },
      }),
      "PRIOR_ACTIVITY",
    ));
    await makeListing(sellerListed, later(0), "active");
    await check("S11", "A seller with a published listing cannot be attributed", "PRIOR_LISTING", () => expectCode(
      () => referrals.claim({
        user: userView(sellerListed),
        body: { code: created.sellerCode, acquisitionKind: "SELLER_ACQUISITION" },
      }),
      "PRIOR_LISTING",
    ));
    await check("S12", "An expired seller referral does not qualify", "ATTRIBUTED", async () => {
      const extra = await makeUser("seller", { societyId: society.id });
      const claimedExtra = await referrals.claim({
        user: userView(extra),
        body: { code: created.sellerCode, acquisitionKind: "SELLER_ACQUISITION" },
      });
      await prisma.incentiveReferral.update({
        where: { id: claimedExtra.referral.id },
        data: { windowEndsAt: new Date(Date.now() - 1000) },
      });
      const when = later(2);
      const listing = await makeListing(extra, when);
      const recorded = await recordListingPublished(prisma, listing);
      await settle(recorded.event.eventId);
      const referral = await prisma.incentiveReferral.findUnique({ where: { id: claimedExtra.referral.id } });
      return { ok: referral.status === "ATTRIBUTED" && !referral.listingPublishedAt, actual: referral.status };
    });

    const sellerTermsFirst = await makeUser("seller", { societyId: society.id });
    await check("S13", "Terms before listing do not qualify before the sale", "QUALIFIED only after sale", async () => {
      const claimedFirst = await referrals.claim({
        user: userView(sellerTermsFirst),
        body: { code: created.sellerCode, acquisitionKind: "SELLER_ACQUISITION" },
      });
      const termsAt = later(2);
      await prisma.sellerTermsAcceptance.create({
        data: { userId: sellerTermsFirst.id, termsVersion: `${PREFIX}-b`, acceptedAt: termsAt },
      });
      const terms = await recordSellerBecameSeller(prisma, { userId: sellerTermsFirst.id, occurredAt: termsAt });
      await settle(terms.event.eventId);
      const afterTerms = await prisma.incentiveReferral.findUnique({ where: { id: claimedFirst.referral.id } });
      const listing = await makeListing(sellerTermsFirst, later(4));
      const published = await recordListingPublished(prisma, listing);
      await settle(published.event.eventId);
      const afterListing = await prisma.incentiveReferral.findUnique({ where: { id: claimedFirst.referral.id } });
      const order = await makeOrder({
        buyer: customer, seller: sellerTermsFirst, listing, status: "completed", when: later(6),
      });
      const emitted = await emitOrderQualifiedIfReady(prisma, order.id);
      await settle(emitted.event.eventId);
      const afterSale = await prisma.incentiveReferral.findUnique({ where: { id: claimedFirst.referral.id } });
      return {
        ok: afterTerms.status === "ATTRIBUTED"
          && afterListing.status === "ATTRIBUTED"
          && afterSale.status === "QUALIFIED",
        actual: `${afterTerms.status}/${afterListing.status}/${afterSale.status}`,
      };
    });

    await check("D10", "Scheduled campaign stays scheduled", "SCHEDULED", async () => {
      await campaignService.setAudiences(campaigns, { campaignId: scheduled.id, actorId, body: { audiences: [{ kind: "BUYERS" }] } });
      await campaignService.setTriggers(campaigns, { campaignId: scheduled.id, actorId, body: { triggers: [{ eventType: "REVIEW_SUBMITTED" }] } });
      await campaignService.setBudget(campaigns, { campaignId: scheduled.id, actorId, body: { amountCap: "10.00" } });
      await campaignService.setRewards(campaigns, {
        campaignId: scheduled.id,
        actorId,
        body: { rewards: [{ slot: "later", recipientRole: "BUYER", rewardType: "POINTS", amount: "1.00" }] },
      });
      await campaignService.setRules(campaigns, { campaignId: scheduled.id, actorId, body: { eligibility: "AUDIENCE_AND_TRIGGER_ONLY" } });
      const saved = await campaignService.changeStatus(campaigns, {
        campaignId: scheduled.id, actorId, to: "ACTIVATE", flags: FLAGS_ON,
      });
      return saved.status === "SCHEDULED";
    });
    await check("D11", "Scheduled campaign can be paused", "PAUSED", async () => {
      const saved = await campaignService.changeStatus(campaigns, {
        campaignId: scheduled.id, actorId, to: "PAUSED", flags: FLAGS_ON,
      });
      return saved.status === "PAUSED";
    });
    await check("D12", "An expired window cannot be activated", "window ended", () => expectCode(async () => {
      await campaignService.setAudiences(campaigns, { campaignId: expired.id, actorId, body: { audiences: [{ kind: "BUYERS" }] } });
      await campaignService.setTriggers(campaigns, { campaignId: expired.id, actorId, body: { triggers: [{ eventType: "REVIEW_SUBMITTED" }] } });
      await campaignService.setBudget(campaigns, { campaignId: expired.id, actorId, body: { amountCap: "10.00" } });
      await campaignService.setRewards(campaigns, {
        campaignId: expired.id,
        actorId,
        body: { rewards: [{ slot: "old", recipientRole: "BUYER", rewardType: "POINTS", amount: "1.00" }] },
      });
      await campaignService.setRules(campaigns, { campaignId: expired.id, actorId, body: { eligibility: "AUDIENCE_AND_TRIGGER_ONLY" } });
      await campaignService.changeStatus(campaigns, { campaignId: expired.id, actorId, to: "ACTIVATE", flags: FLAGS_ON });
    }, undefined).then((result) => ({ ok: result.actual !== "no error", actual: result.actual })));
    await check("D13", "Editing a published campaign forks a draft", "published snapshot unchanged", async () => {
      const activated = await campaignService.changeStatus(campaigns, {
        campaignId: promo.id, actorId, to: "ACTIVATE", flags: FLAGS_ON,
      });
      const publishedId = activated.version.id;
      const publishedBefore = await prisma.incentiveCampaignVersion.findUnique({ where: { id: publishedId } });
      const edited = await campaignService.updateCampaign(campaigns, {
        campaignId: promo.id, actorId, body: { description: `${PREFIX} edited` },
      });
      const publishedAfter = await prisma.incentiveCampaignVersion.findUnique({ where: { id: publishedId } });
      return {
        ok: edited.status === "DRAFT"
          && edited.version.id !== publishedId
          && publishedAfter.publishedAt
          && JSON.stringify(publishedBefore.snapshot) === JSON.stringify(publishedAfter.snapshot),
        actual: `status=${edited.status} sameVersion=${edited.version.id === publishedId}`,
      };
    });
    await check("D14", "Simulation writes no reward, coupon, or ledger row", "unchanged counts", async () => {
      const before = {
        rewards: await prisma.incentiveReward.count(),
        coupons: await prisma.coupon.count(),
        ledger: await prisma.incentiveLedgerEntry.count(),
      };
      const version = await prisma.incentiveCampaignVersion.findFirst({
        where: { campaignId: promo.id, publishedAt: { not: null } },
        orderBy: { versionNumber: "asc" },
      });
      await campaignService.simulate(campaigns, {
        campaignId: promo.id,
        versionId: version.id,
        attributes: { "user.role": "buyer", "order.total": 80, "order.itemCount": 1 },
      });
      const after = {
        rewards: await prisma.incentiveReward.count(),
        coupons: await prisma.coupon.count(),
        ledger: await prisma.incentiveLedgerEntry.count(),
      };
      return {
        ok: before.rewards === after.rewards && before.coupons === after.coupons && before.ledger === after.ledger,
        actual: JSON.stringify({ before, after }),
      };
    });
    await check("D15", "Duplicating a campaign leaves the source status unchanged", "source unchanged", async () => {
      const sourceBefore = await prisma.incentiveCampaign.findUnique({ where: { id: buyerCampaign.id } });
      const copy = await campaignService.duplicateCampaign(campaigns, {
        campaignId: buyerCampaign.id, actorId, body: { name: `${PREFIX} buyer copy` },
      });
      owned.campaignIds.push(copy.id);
      const sourceAfter = await prisma.incentiveCampaign.findUnique({ where: { id: buyerCampaign.id } });
      return {
        ok: sourceBefore.status === sourceAfter.status && sourceBefore.currentVersionId === sourceAfter.currentVersionId && copy.id !== sourceBefore.id,
        actual: `${sourceBefore.status}->${sourceAfter.status}`,
      };
    });

    const rangeFrom = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const rangeTo = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    await check("E01", "Referral analytics match the referral table", "same counts", async () => {
      const report = await referralAnalytics(prisma, {
        query: { campaignId: buyerCampaign.id, from: rangeFrom, to: rangeTo },
        now: new Date(),
      });
      const rows = await prisma.incentiveReferral.groupBy({
        by: ["status"],
        where: { campaignId: buyerCampaign.id, acquisitionKind: "BUYER_ACQUISITION" },
        _count: { _all: true },
      });
      const sqlAttributed = rows.reduce((sum, row) => sum + row._count._all, 0);
      const sqlQualified = rows.filter((row) => row.status === "QUALIFIED").reduce((sum, row) => sum + row._count._all, 0);
      return {
        ok: report.funnel.codesAttributed === sqlAttributed && report.funnel.qualified === sqlQualified,
        actual: `report=${report.funnel.codesAttributed}/${report.funnel.qualified} sql=${sqlAttributed}/${sqlQualified}`,
      };
    });
    await check("E02", "Buyer and seller funnels stay separated", "separate counts", async () => {
      const report = await referralAnalytics(prisma, { query: { from: rangeFrom, to: rangeTo }, now: new Date() });
      const buyer = await prisma.incentiveReferral.count({
        where: { campaignId: { in: owned.campaignIds }, acquisitionKind: "BUYER_ACQUISITION" },
      });
      const seller = await prisma.incentiveReferral.count({
        where: { campaignId: { in: owned.campaignIds }, acquisitionKind: "SELLER_ACQUISITION" },
      });
      return {
        ok: report.comparison.BUYER_ACQUISITION.attributed >= buyer
          && report.comparison.SELLER_ACQUISITION.attributed >= seller
          && report.comparison.BUYER_ACQUISITION.attributed !== report.comparison.SELLER_ACQUISITION.attributed,
        actual: `buyer ${report.comparison.BUYER_ACQUISITION.attributed}/${buyer} seller ${report.comparison.SELLER_ACQUISITION.attributed}/${seller}`,
      };
    });
    await check("E03", "Reward report matches reward rows", "same issued count", async () => {
      const report = await rewardReport(prisma, {
        query: { campaignId: buyerCampaign.id, from: rangeFrom, to: rangeTo },
        now: new Date(),
      });
      const sql = await prisma.incentiveReward.count({
        where: { status: "ISSUED", campaignVersion: { campaignId: buyerCampaign.id } },
      });
      return { ok: report.counts.ISSUED === sql, actual: `report=${report.counts.ISSUED} sql=${sql}` };
    });
    await check("E04", "Leader order matches the qualified-referral aggregate", "same leader", async () => {
      const report = await referralAnalytics(prisma, {
        query: { campaignId: buyerCampaign.id, from: rangeFrom, to: rangeTo, audience: "BUYER" },
        now: new Date(),
      });
      const grouped = await prisma.incentiveReferral.groupBy({
        by: ["referrerUserId"],
        where: { campaignId: buyerCampaign.id, status: "QUALIFIED", acquisitionKind: "BUYER_ACQUISITION" },
        _count: { _all: true },
        orderBy: { _count: { referrerUserId: "desc" } },
      });
      const leader = report.leaders[0];
      const sqlLeader = grouped[0];
      if (!leader && !sqlLeader) return { ok: true, actual: "empty" };
      return {
        ok: Boolean(leader && sqlLeader) && leader.userId === sqlLeader.referrerUserId && leader.qualified === sqlLeader._count._all,
        actual: leader ? `${leader.userId}:${leader.qualified}` : "none",
      };
    });
    await check("E05", "Audit page length matches the capped audit query", "same page", async () => {
      const page = await auditPage(prisma, { query: { campaignId: buyerCampaign.id, from: rangeFrom, to: rangeTo } });
      const sql = await prisma.incentiveAuditLog.count({
        where: { campaignId: buyerCampaign.id, createdAt: { gte: new Date(rangeFrom), lt: new Date(rangeTo) } },
      });
      const expected = Math.min(sql, 20);
      return {
        ok: page.entries.length === expected && (sql <= 20 ? page.nextCursor == null : Boolean(page.nextCursor)),
        actual: `page=${page.entries.length} sql=${sql}`,
      };
    });
    await check("E06", "A past date range returns no rows for this run", "zero", async () => {
      const report = await referralAnalytics(prisma, {
        query: { campaignId: buyerCampaign.id, from: "2020-01-01T00:00:00.000Z", to: "2020-02-01T00:00:00.000Z" },
        now: new Date(),
      });
      const sql = await prisma.incentiveReferral.count({
        where: {
          campaignId: buyerCampaign.id,
          attributedAt: { gte: new Date("2020-01-01T00:00:00.000Z"), lt: new Date("2020-02-01T00:00:00.000Z") },
        },
      });
      return { ok: report.funnel.codesAttributed === 0 && sql === 0, actual: `report=${report.funnel.codesAttributed} sql=${sql}` };
    });
    await check("E07", "An invalid date range is rejected", "RANGE_INVALID", () => expectCode(
      () => referralAnalytics(prisma, { query: { from: "not-a-date", to: rangeTo }, now: new Date() }),
      "RANGE_INVALID",
    ));
    await check("E08", "A reversed date range is rejected", "RANGE_INVALID", () => expectCode(
      () => referralAnalytics(prisma, { query: { from: rangeTo, to: rangeFrom }, now: new Date() }),
      "RANGE_INVALID",
    ));
    await check("E09", "Failed-event report matches failed rows for this run", "same count", async () => {
      const sql = await prisma.incentiveEvent.count({
        where: { entityId: { in: owned.entityIds }, status: "FAILED" },
      });
      const listed = await events.listEvents({ status: "FAILED", limit: 50 });
      const ours = listed.filter((row) => owned.entityIds.includes(row.entityId));
      return { ok: ours.length === Math.min(sql, 50), actual: `listed=${ours.length} sql=${sql}` };
    });
    await check("E10", "Risk indicators do not change the user", "unchanged", async () => {
      const before = await prisma.user.findUnique({ where: { id: buyerA.id } });
      await risk(prisma, { query: { campaignId: buyerCampaign.id, from: rangeFrom, to: rangeTo }, now: new Date() });
      const after = await prisma.user.findUnique({ where: { id: buyerA.id } });
      return {
        ok: before.role === after.role && before.suspended === after.suspended,
        actual: `${before.role}/${before.suspended}`,
      };
    });

    const history = await listOwnRewards(prisma, buyerA.id, {});
    await check("F01", "Buyer A sees only rewards addressed to Buyer A", "own rewards", async () => {
      const foreign = history.rewards.filter((row) => row.recipientUserId && row.recipientUserId !== buyerA.id);
      const ownIds = new Set(history.rewards.map((row) => row.id));
      const sellerRewards = await prisma.incentiveReward.findMany({ where: { recipientUserId: sellerA.id }, select: { id: true } });
      return {
        ok: foreign.length === 0 && sellerRewards.every((row) => !ownIds.has(row.id)),
        actual: `visible=${history.rewards.length} foreign=${foreign.length}`,
      };
    });
    await check("F02", "Seller B cannot list Seller A's referral code", "hidden", async () => {
      const visible = await listReferralCodes(codeRepository, { user: userView(sellerB) });
      return {
        ok: visible.codes.every((row) => row.code !== created.sellerCode),
        actual: `codes=${visible.codes.length}`,
      };
    });
    const app = express();
    app.use(express.json());
    app.use("/incentive/admin", createRewardsRouter());
    app.use("/incentive", createMyRewardsRouter());
    server = await new Promise((resolve) => {
      const listening = http.createServer(app);
      listening.listen(0, "127.0.0.1", () => resolve(listening));
    });
    const port = server.address().port;
    async function call(method, path, token) {
      const response = await fetch(`http://127.0.0.1:${port}${path}`, {
        method,
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      });
      const body = await response.json().catch(() => ({}));
      return { status: response.status, body };
    }
    await check("F03", "A buyer cannot open the admin reward overview", "403", async () => {
      const response = await call("GET", "/incentive/admin/overview", signToken(buyerB));
      return { ok: response.status === 403, actual: String(response.status) };
    });
    await check("F04", "Portal admin can read the reward overview", "200", async () => {
      const response = await call("GET", "/incentive/admin/overview", signToken(portal));
      return { ok: response.status === 200, actual: String(response.status) };
    });
    await check("F05", "Portal admin cannot approve a reward", "403", async () => {
      const response = await call("POST", "/incentive/admin/rewards/not-a-reward/approve", signToken(portal));
      return { ok: response.status === 403, actual: String(response.status) };
    });
    await check("F06", "Buyer reward history ignores a requested user id", "own history", async () => {
      const response = await call("GET", `/incentive/rewards/history?userId=${sellerA.id}`, signToken(buyerA));
      const ids = (response.body.entries || []).map((row) => row.rewardId);
      const sellerRewardIds = new Set((await prisma.incentiveReward.findMany({
        where: { recipientUserId: sellerA.id }, select: { id: true },
      })).map((row) => row.id));
      return {
        ok: response.status === 200 && ids.every((id) => !sellerRewardIds.has(id)),
        actual: `status=${response.status} entries=${ids.length}`,
      };
    });
  } finally {
    if (server) await new Promise((resolve) => server.close(resolve));
    let cleanupError = null;
    try {
      await prisma.incentiveSetting.deleteMany({ where: { key: { in: Object.values(FLAG_KEYS) } } });
      if (originalSettings.length) {
        await prisma.incentiveSetting.createMany({
          data: originalSettings.map((row) => ({ key: row.key, value: row.value })),
          skipDuplicates: true,
        });
      }
      const released = [];
      await prisma.$transaction(async (tx) => {
        if (owned.campaignIds.length) {
          const linked = await tx.$queryRaw`
            SELECT reward."couponId" AS id
            FROM "IncentiveReward" AS reward
            JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
            WHERE version."campaignId" IN (${Prisma.join(owned.campaignIds)})
              AND reward."couponId" IS NOT NULL
          `;
          for (const row of linked) if (row.id) released.push(row.id);
        }
        await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" DISABLE TRIGGER USER`;
        if (owned.campaignIds.length) {
          await tx.$executeRaw`
            DELETE FROM "IncentiveLedgerEntry"
            WHERE "rewardId" IN (
              SELECT reward."id" FROM "IncentiveReward" AS reward
              JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
              WHERE version."campaignId" IN (${Prisma.join(owned.campaignIds)})
            )`;
          await tx.$executeRaw`
            DELETE FROM "IncentiveRedemption"
            WHERE "rewardId" IN (
              SELECT reward."id" FROM "IncentiveReward" AS reward
              JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
              WHERE version."campaignId" IN (${Prisma.join(owned.campaignIds)})
            )`;
          await tx.$executeRaw`
            DELETE FROM "IncentiveApproval"
            WHERE "rewardId" IN (
              SELECT reward."id" FROM "IncentiveReward" AS reward
              JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
              WHERE version."campaignId" IN (${Prisma.join(owned.campaignIds)})
            )`;
          await tx.$executeRaw`
            DELETE FROM "IncentiveReward" AS reward
            USING "IncentiveCampaignVersion" AS version
            WHERE reward."campaignVersionId" = version."id"
              AND version."campaignId" IN (${Prisma.join(owned.campaignIds)})`;
        }
        await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" ENABLE TRIGGER USER`;
      });
      owned.couponIds.push(...released);
      if (owned.entityIds.length) {
        await prisma.incentiveEvent.deleteMany({ where: { entityId: { in: [...new Set(owned.entityIds)] } } });
      }
      if (owned.campaignIds.length) {
        await prisma.incentiveAuditLog.deleteMany({ where: { campaignId: { in: owned.campaignIds } } });
        await prisma.incentiveReferral.deleteMany({ where: { campaignId: { in: owned.campaignIds } } });
        await prisma.incentiveReferralCode.deleteMany({ where: { campaignId: { in: owned.campaignIds } } });
        await prisma.incentiveCampaign.updateMany({
          where: { id: { in: owned.campaignIds } },
          data: { currentVersionId: null },
        });
        await prisma.incentiveCampaignVersion.deleteMany({ where: { campaignId: { in: owned.campaignIds } } });
        await prisma.incentiveCampaign.deleteMany({ where: { id: { in: owned.campaignIds } } });
      }
      if (owned.couponIds.length) {
        await prisma.couponRedemption.deleteMany({ where: { couponId: { in: owned.couponIds } } });
        await prisma.couponEligibleUser.deleteMany({ where: { couponId: { in: owned.couponIds } } });
        await prisma.coupon.deleteMany({ where: { id: { in: owned.couponIds } } });
      }
      if (owned.orderIds.length) {
        await prisma.orderItem.deleteMany({ where: { orderId: { in: owned.orderIds } } });
        await prisma.order.deleteMany({ where: { id: { in: owned.orderIds } } });
      }
      if (owned.listingIds.length) await prisma.listing.deleteMany({ where: { id: { in: owned.listingIds } } });
      if (owned.userIds.length) {
        await prisma.sellerTermsAcceptance.deleteMany({ where: { userId: { in: owned.userIds } } });
        await prisma.user.deleteMany({ where: { id: { in: owned.userIds } } });
      }
      if (owned.societyIds.length) await prisma.society.deleteMany({ where: { id: { in: owned.societyIds } } });
    } catch (error) {
      cleanupError = error;
      console.log(`CLEANUP_FAILED ${scrub(error && error.stack ? error.stack : error)}`);
    }
    try {
      const triggers = await triggerStates(prisma);
      const enabled = LEDGER_TRIGGERS.every((name) => triggers[name] === "O");
      const settings = await prisma.incentiveSetting.findMany();
      const flagsOn = settings.some((row) => String(row.value).replace(/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/g, "") === "true");
      const afterCounts = await tableCounts(prisma);
      console.log(`AFTER_COUNTS ${JSON.stringify(afterCounts)}`);
      console.log(`LEDGER_TRIGGER_STATE ${JSON.stringify(triggers)}`);
      console.log(`FLAG_ROWS ${settings.length} FLAGS_ON ${flagsOn ? "yes" : "no"}`);
      if (beforeCounts) {
        const deltas = {};
        for (const key of Object.keys(beforeCounts)) {
          if (beforeCounts[key] !== afterCounts[key]) deltas[key] = afterCounts[key] - beforeCounts[key];
        }
        console.log(`COUNT_DELTAS ${JSON.stringify(deltas)}`);
      }
      if (!enabled) console.log("CLEANUP_TRIGGER_DISABLED");
      if (flagsOn) console.log("CLEANUP_FLAGS_LEFT_ON");
      if (!cleanupError && enabled && !flagsOn) console.log("CLEANUP_OK");
    } catch (error) {
      console.log(`CLEANUP_VERIFY_FAILED ${scrub(error.message)}`);
    }
    await prisma.$queryRaw`SELECT pg_advisory_unlock(${LOCK_A}::int, ${LOCK_B}::int)`.catch(() => {});
    await prisma.$disconnect();
  }

  const summary = results.reduce((counts, row) => {
    counts[row.status] = (counts[row.status] || 0) + 1;
    counts.total += 1;
    return counts;
  }, { total: 0 });
  console.log(`PHASE3_JOURNEY_SUMMARY ${JSON.stringify(summary)}`);
  if (results.some((row) => row.status !== "PASS")) process.exitCode = 1;
}

main().catch((error) => {
  console.log(`PHASE3_JOURNEY_FATAL ${scrub(error && error.stack ? error.stack : error)}`);
  process.exitCode = 1;
});
