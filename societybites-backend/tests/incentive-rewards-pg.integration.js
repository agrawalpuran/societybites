/**
 * Local PostgreSQL checks for reward issuance and the ledger guard.
 * Not part of npm test. Does not apply a migration and does not read .env.
 * Run only after 20261117233000_incentive_ledger_guard has been applied with
 * psql to 127.0.0.1:5432/societybites_incentive_foundation.
 * Two Prisma clients are two database sessions. Event retry is sequential
 * because a retry starts only after the failed attempt has committed.
 * The foundation database has no Coupon table. Coupon-row rollback is in
 * tests/incentive-rewards-coupon-pg.integration.js. This file still proves
 * that a failed coupon write rolls back the reward and the budget reservation.
 * Cleanup of committed ledger rows runs after the assertions. It disables the
 * append-only triggers, deletes this prefix, and enables the triggers inside
 * one transaction. A failed cleanup rolls the disable back. The run then
 * queries pg_trigger and stops if any of the three triggers is not enabled.
 */
const crypto = require("crypto");
const { PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("../lib/prismaPool");
const { createPrismaEventRepository } = require("../modules/incentive-engine/events/repository");
const { evaluateClaimed } = require("../modules/incentive-engine/events/process");
const { issueMatchedRewards } = require("../modules/incentive-engine/rewards/issue");
const { approveReward, redeemReward, rejectReward } = require("../modules/incentive-engine/rewards/approve");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_foundation";
const PREFIX = `p2e${crypto.randomBytes(6).toString("hex")}`;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertSafeUrl(value) {
  if (!value || typeof value !== "string") throw new Error("DATABASE_URL must be set before this test starts");
  const lowered = value.toLowerCase();
  if (lowered.includes("supabase") || lowered.includes("pooler.supabase")) {
    throw new Error("DATABASE_URL must not point at Supabase");
  }
  const parsed = new URL(value);
  const database = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  if (parsed.hostname !== REQUIRED_HOST) throw new Error(`host must be ${REQUIRED_HOST}`);
  if ((parsed.port || REQUIRED_PORT) !== REQUIRED_PORT) throw new Error(`port must be ${REQUIRED_PORT}`);
  if (database !== REQUIRED_DATABASE) throw new Error(`database must be ${REQUIRED_DATABASE}`);
}

function localClient(url) {
  const bounded = new URL(withPrismaPoolParams(url));
  bounded.searchParams.set("connection_limit", "1");
  return new PrismaClient({ datasources: { db: { url: bounded.toString() } } });
}

function asNumber(value) {
  return Number(String(value));
}

async function sessionPid(prisma) {
  const rows = await prisma.$queryRaw`SELECT pg_backend_pid() AS pid`;
  return Number(rows[0].pid);
}

function snapshot(slot, amount, rewardType = "PROMOTIONAL_CREDIT") {
  return {
    eligibility: "AUDIENCE_AND_TRIGGER_ONLY",
    audiences: [{ kind: "ALL_USERS", payload: {} }],
    triggers: [{ eventType: "USER_REGISTERED" }],
    rewards: [{
      slot,
      recipientRole: "TRIGGER_USER",
      rewardType,
      amount,
      expiryDays: 30,
    }],
    budget: { amountCap: "100.00", currency: "INR" },
  };
}

async function createVersion(prisma, { cap, issued = "0.00", slot = "credit", amount = "10.00", rewardType = "PROMOTIONAL_CREDIT" }) {
  const body = snapshot(slot, amount, rewardType);
  body.budget.amountCap = String(cap);
  const campaign = await prisma.incentiveCampaign.create({
    data: {
      name: PREFIX,
      category: "REPEAT_ORDER",
      status: "ACTIVE",
      stackingMode: "STACK",
      priority: 1,
    },
  });
  const version = await prisma.incentiveCampaignVersion.create({
    data: {
      campaignId: campaign.id,
      versionNumber: 1,
      snapshot: body,
      publishedAt: new Date("2026-11-17T00:00:00.000Z"),
    },
  });
  await prisma.incentiveCampaign.update({
    where: { id: campaign.id },
    data: { currentVersionId: version.id },
  });
  await prisma.incentiveBudget.create({
    data: { versionId: version.id, amountCap: cap, issuedAmount: issued, currency: "INR" },
  });
  return { campaign, version, body };
}

async function createEvent(prisma, suffix, extra = {}) {
  return prisma.incentiveEvent.create({
    data: {
      eventId: `${PREFIX}-${suffix}`,
      type: "USER_REGISTERED",
      entityType: "user",
      entityId: `${PREFIX}-user`,
      userId: `${PREFIX}-user`,
      occurredAt: new Date("2026-11-17T12:00:00.000Z"),
      payload: {},
      status: "PROCESSED",
      ...extra,
    },
  });
}

function issueInput(version, event, body) {
  return {
    event: { id: event.id, type: event.type, userId: event.userId, entityId: event.entityId },
    matches: [{ campaignId: version.campaignId, passed: true }],
    campaigns: [{
      id: version.campaignId,
      stackingMode: "STACK",
      priority: 1,
      version: { id: version.id, snapshot: body },
    }],
    flags: { issuance: true },
    now: new Date("2026-11-17T12:00:00.000Z"),
  };
}

async function balance(prisma, rewardId) {
  const rows = await prisma.$queryRaw`
    SELECT COALESCE(SUM("amount"), 0) AS total
    FROM "IncentiveLedgerEntry"
    WHERE "rewardId" = ${rewardId}
  `;
  return asNumber(rows[0].total);
}

async function issuedAmount(prisma, versionId) {
  const budget = await prisma.incentiveBudget.findUnique({ where: { versionId } });
  return asNumber(budget.issuedAmount);
}

async function removeOwned(prisma) {
  const pattern = `%${PREFIX}%`;
  await prisma.$transaction(async (tx) => {
    await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" DISABLE TRIGGER USER`;
    try {
      await deleteOwned(tx, pattern);
    } finally {
      await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" ENABLE TRIGGER USER`;
    }
  });
}

async function deleteOwned(tx, pattern) {
  await tx.$executeRaw`
      DELETE FROM "IncentiveLedgerEntry"
      WHERE "idempotencyKey" LIKE ${pattern}
         OR "rewardId" IN (
           SELECT r."id"
           FROM "IncentiveReward" AS r
           JOIN "IncentiveCampaignVersion" AS v ON v."id" = r."campaignVersionId"
           JOIN "IncentiveCampaign" AS c ON c."id" = v."campaignId"
           WHERE c."name" = ${PREFIX}
         )
    `;
    await tx.$executeRaw`
      DELETE FROM "IncentiveRedemption"
      WHERE "rewardId" IN (
        SELECT r."id"
        FROM "IncentiveReward" AS r
        JOIN "IncentiveCampaignVersion" AS v ON v."id" = r."campaignVersionId"
        JOIN "IncentiveCampaign" AS c ON c."id" = v."campaignId"
        WHERE c."name" = ${PREFIX}
      )
    `;
    await tx.$executeRaw`
      DELETE FROM "IncentiveApproval"
      WHERE "rewardId" IN (
        SELECT r."id"
        FROM "IncentiveReward" AS r
        JOIN "IncentiveCampaignVersion" AS v ON v."id" = r."campaignVersionId"
        JOIN "IncentiveCampaign" AS c ON c."id" = v."campaignId"
        WHERE c."name" = ${PREFIX}
      )
    `;
    await tx.$executeRaw`
      DELETE FROM "IncentiveReward" AS r
      USING "IncentiveCampaignVersion" AS v, "IncentiveCampaign" AS c
      WHERE r."campaignVersionId" = v."id"
        AND v."campaignId" = c."id"
        AND c."name" = ${PREFIX}
    `;
    await tx.$executeRaw`
      DELETE FROM "IncentiveAuditLog"
      WHERE "actorId" = ${PREFIX}
         OR "incentiveEventId" IN (
           SELECT "id" FROM "IncentiveEvent" WHERE "eventId" LIKE ${pattern}
         )
         OR "campaignId" IN (
           SELECT "id" FROM "IncentiveCampaign" WHERE "name" = ${PREFIX}
         )
    `;
    await tx.$executeRaw`DELETE FROM "IncentiveEvent" WHERE "eventId" LIKE ${pattern}`;
    await tx.$executeRaw`
      DELETE FROM "IncentiveBudget"
      WHERE "versionId" IN (
        SELECT v."id"
        FROM "IncentiveCampaignVersion" AS v
        JOIN "IncentiveCampaign" AS c ON c."id" = v."campaignId"
        WHERE c."name" = ${PREFIX}
      )
    `;
    await tx.$executeRaw`
      DELETE FROM "IncentiveCampaignVersion"
      WHERE "campaignId" IN (SELECT "id" FROM "IncentiveCampaign" WHERE "name" = ${PREFIX})
    `;
    await tx.$executeRaw`DELETE FROM "IncentiveCampaign" WHERE "name" = ${PREFIX}`;
}

async function assertTriggersEnabled(prisma) {
  let triggers;
  try {
    triggers = await prisma.$queryRaw`
      SELECT tgname, tgenabled
      FROM pg_trigger
      WHERE tgname IN ('incentive_ledger_no_update', 'incentive_ledger_no_delete', 'incentive_ledger_guard_insert')
        AND tgrelid = '"IncentiveLedgerEntry"'::regclass
    `;
  } catch (error) {
    console.error("LEDGER_TRIGGER_RESTORATION_FAILED");
    console.error(error);
    throw new Error("LEDGER_TRIGGER_RESTORATION_FAILED");
  }
  const enabled = triggers.length === 3 && triggers.every((row) => row.tgenabled === "O");
  if (!enabled) {
    console.error("LEDGER_TRIGGER_RESTORATION_FAILED");
    console.error(triggers);
    throw new Error("LEDGER_TRIGGER_RESTORATION_FAILED");
  }
}

async function assertGone(prisma) {
  const campaigns = await prisma.incentiveCampaign.count({ where: { name: PREFIX } });
  const events = await prisma.incentiveEvent.count({ where: { eventId: { startsWith: PREFIX } } });
  const ledger = await prisma.$queryRaw`
    SELECT COUNT(*)::int AS count
    FROM "IncentiveLedgerEntry"
    WHERE "idempotencyKey" LIKE ${`%${PREFIX}%`}
  `;
  const rewards = await prisma.$queryRaw`
    SELECT COUNT(*)::int AS count
    FROM "IncentiveReward" AS r
    JOIN "IncentiveCampaignVersion" AS v ON v."id" = r."campaignVersionId"
    JOIN "IncentiveCampaign" AS c ON c."id" = v."campaignId"
    WHERE c."name" = ${PREFIX}
  `;
  assert(campaigns === 0 && events === 0 && Number(ledger[0].count) === 0 && Number(rewards[0].count) === 0, "test-owned rows remain");
  const triggers = await prisma.$queryRaw`
    SELECT tgenabled
    FROM pg_trigger
    WHERE tgname IN ('incentive_ledger_no_update', 'incentive_ledger_no_delete', 'incentive_ledger_guard_insert')
      AND tgrelid = '"IncentiveLedgerEntry"'::regclass
  `;
  assert(triggers.length === 3 && triggers.every((row) => row.tgenabled === "O"), "ledger triggers were not re-enabled");
}

async function expectReject(work, text) {
  try {
    await work();
  } catch (error) {
    assert(String(error && error.message).includes(text), `expected ${text}`);
    return;
  }
  throw new Error(`${text} was allowed`);
}

async function main() {
  assertSafeUrl(process.env.DATABASE_URL);
  const left = localClient(process.env.DATABASE_URL);
  const right = localClient(process.env.DATABASE_URL);
  let started = false;
  let failure = null;
  try {
    let definition = "";
    try {
      const guard = await left.$queryRaw`
        SELECT pg_get_functiondef('incentive_ledger_guard_insert()'::regprocedure) AS definition
      `;
      definition = String(guard[0] && guard[0].definition || "");
    } catch (error) {
      definition = "";
    }
    if (!definition.includes("FOR UPDATE") || !definition.includes("IncentiveReward")) {
      console.log("LEDGER_GUARD_NOT_APPLIED");
      return;
    }
    const leftPid = await sessionPid(left);
    const rightPid = await sessionPid(right);
    assert(leftPid !== rightPid, "the two clients must be different PostgreSQL sessions");
    started = true;

    const marker = `${PREFIX}-rollback`;
    await left.$transaction(async (tx) => {
      await tx.incentiveCampaign.create({
        data: { name: marker, category: "REPEAT_ORDER", status: "DRAFT" },
      });
      throw new Error("ROLLBACK_TEST");
    }).catch((error) => {
      if (error.message !== "ROLLBACK_TEST") throw error;
    });
    assert(await left.incentiveCampaign.count({ where: { name: marker } }) === 0, "a rolled-back campaign remains");

    const base = await createVersion(left, { cap: "100.00", amount: "10.00" });
    const seedEvent = await createEvent(left, "seed");
    const seeded = await left.$transaction((tx) => issueMatchedRewards(tx, issueInput(base.version, seedEvent, base.body)));
    const rewardId = seeded.issued[0].id;
    assert(await balance(left, rewardId) === 10, "seed balance is 10");

    const debits = await Promise.allSettled([
      left.$transaction((tx) => tx.incentiveLedgerEntry.create({
        data: { rewardId, entryType: "REDEEM", amount: "-6.00", idempotencyKey: `${PREFIX}-debit-a` },
      })),
      right.$transaction((tx) => tx.incentiveLedgerEntry.create({
        data: { rewardId, entryType: "REDEEM", amount: "-6.00", idempotencyKey: `${PREFIX}-debit-b` },
      })),
    ]);
    assert(debits.filter((row) => row.status === "fulfilled").length === 1, "one debit of 6 commits");
    assert(debits.filter((row) => row.status === "rejected").length === 1, "the other debit of 6 is rejected");
    assert(await balance(left, rewardId) === 4, "two debits of 6 against 10 finish at 4");

    const other = await createVersion(left, { cap: "100.00", amount: "10.00" });
    const otherEvent = await createEvent(left, "other");
    const otherIssued = await left.$transaction((tx) => issueMatchedRewards(tx, issueInput(other.version, otherEvent, other.body)));
    const pair = await Promise.allSettled([
      left.$transaction((tx) => tx.incentiveLedgerEntry.create({
        data: { rewardId, entryType: "REDEEM", amount: "-1.00", idempotencyKey: `${PREFIX}-debit-c` },
      })),
      right.$transaction((tx) => tx.incentiveLedgerEntry.create({
        data: {
          rewardId: otherIssued.issued[0].id,
          entryType: "REDEEM",
          amount: "-6.00",
          idempotencyKey: `${PREFIX}-debit-other`,
        },
      })),
    ]);
    assert(pair.every((row) => row.status === "fulfilled"), "debits of different rewards both commit");
    assert(await balance(left, otherIssued.issued[0].id) === 4, "a different reward keeps its own balance");

    const redeemVersion = await createVersion(left, { cap: "100.00", amount: "10.00" });
    const redeemEvent = await createEvent(left, "redeem");
    const redeemIssued = await left.$transaction((tx) => issueMatchedRewards(tx, issueInput(redeemVersion.version, redeemEvent, redeemVersion.body)));
    const redeemId = redeemIssued.issued[0].id;
    const redemptions = await Promise.allSettled([
      left.$transaction((tx) => redeemReward(tx, {
        rewardId: redeemId,
        amount: "6.00",
        actorId: PREFIX,
        idempotencyKey: `${PREFIX}-use-a`,
        flags: { redemption: true },
      })),
      right.$transaction((tx) => redeemReward(tx, {
        rewardId: redeemId,
        amount: "6.00",
        actorId: PREFIX,
        idempotencyKey: `${PREFIX}-use-b`,
        flags: { redemption: true },
      })),
    ]);
    assert(redemptions.filter((row) => row.status === "fulfilled").length === 1, "one redemption commits");
    assert(redemptions.filter((row) => row.status === "rejected").length === 1, "the other redemption key is rejected");
    assert(await balance(left, redeemId) === 4, "different redemption keys cannot both debit 6 from 10");

    const limited = await createVersion(left, { cap: "20.00", issued: "10.00", amount: "10.00" });
    const pending = await left.incentiveReward.create({
      data: {
        campaignVersionId: limited.version.id,
        rewardSlot: "credit",
        recipientUserId: `${PREFIX}-user`,
        sourceEventId: `${PREFIX}-pending`,
        status: "PENDING_APPROVAL",
        amount: "10.00",
        idempotencyKey: `${PREFIX}-pending-key`,
      },
    });
    const freshBody = snapshot("fresh", "15.00");
    freshBody.budget.amountCap = "20.00";
    const freshEvent = await createEvent(left, "fresh");
    const race = await Promise.allSettled([
      left.$transaction((tx) => rejectReward(tx, { rewardId: pending.id, actorId: PREFIX, reason: "No" })),
      right.$transaction((tx) => issueMatchedRewards(tx, issueInput(
        { id: limited.version.id, campaignId: limited.campaign.id },
        freshEvent,
        freshBody
      ))),
    ]);
    assert(race.every((row) => row.status === "fulfilled"), "rejection and issuance both finish");
    const racedAmount = await issuedAmount(left, limited.version.id);
    const freshCount = await left.incentiveReward.count({
      where: { campaignVersionId: limited.version.id, rewardSlot: "fresh" },
    });
    assert(racedAmount === 15 || racedAmount === 0, "rejection and issuance do not leave a stale budget");
    assert(freshCount === (racedAmount === 15 ? 1 : 0), "the new credit exists only when the budget can hold it");
    await left.$transaction((tx) => rejectReward(tx, { rewardId: pending.id, actorId: PREFIX }));
    assert(await issuedAmount(left, limited.version.id) === racedAmount, "rejecting the same reward twice does not release the budget again");

    const crowded = await createVersion(left, { cap: "15.00", amount: "15.00" });
    const crowdA = await createEvent(left, "crowd-a");
    const crowdB = await createEvent(left, "crowd-b");
    const crowd = await Promise.all([
      left.$transaction((tx) => issueMatchedRewards(tx, issueInput(crowded.version, crowdA, crowded.body))),
      right.$transaction((tx) => issueMatchedRewards(tx, issueInput(crowded.version, crowdB, crowded.body))),
    ]);
    assert(crowd.reduce((sum, row) => sum + row.issued.length, 0) === 1, "concurrent issuance stops at the campaign budget");
    assert(await issuedAmount(left, crowded.version.id) === 15, "budget consumption stays at the cap");

    const duplicateVersion = await createVersion(left, { cap: "100.00", amount: "10.00" });
    const duplicateEvent = await createEvent(left, "same");
    await Promise.all([
      left.$transaction((tx) => issueMatchedRewards(tx, issueInput(duplicateVersion.version, duplicateEvent, duplicateVersion.body))),
      right.$transaction((tx) => issueMatchedRewards(tx, issueInput(duplicateVersion.version, duplicateEvent, duplicateVersion.body))),
    ]);
    assert(await left.incentiveReward.count({ where: { sourceEventId: duplicateEvent.id } }) === 1, "two sessions do not create two rewards for one event");
    assert(await issuedAmount(left, duplicateVersion.version.id) === 10, "the duplicate event charges the budget once");

    const couponVersion = await createVersion(left, { cap: "100.00", rewardType: "FIXED_COUPON", amount: "20.00" });
    const couponEvent = await createEvent(left, "coupon-fail");
    let couponError = null;
    try {
      await left.$transaction(async (tx) => {
        const saved = await issueMatchedRewards(tx, issueInput(couponVersion.version, couponEvent, couponVersion.body));
        assert(saved.issued.length === 1, "coupon reward was not created before rollback");
        throw new Error("ROLLBACK_COUPON");
      });
    } catch (error) {
      couponError = error;
    }
    const couponTable = await left.$queryRaw`SELECT to_regclass('"Coupon"')::text AS name`;
    if (!couponTable[0].name) {
      console.log("COUPON_TABLE_ABSENT_ON_FOUNDATION");
      assert(couponError && !String(couponError.message).includes("ROLLBACK_COUPON"), "coupon creation on a database without Coupon must fail");
    } else {
      assert(couponError && couponError.message === "ROLLBACK_COUPON", "a present Coupon table must roll the issuance back");
    }
    assert(await left.incentiveReward.count({ where: { sourceEventId: couponEvent.id } }) === 0, "failed coupon issuance left a reward");
    assert(await issuedAmount(left, couponVersion.version.id) === 0, "failed coupon issuance left a budget reservation");

    const foreign = await left.incentiveCampaign.count({
      where: { status: { in: ["ACTIVE", "SCHEDULED"] }, name: { not: PREFIX } },
    });
    assert(foreign === 0, "FOREIGN_ACTIVE_CAMPAIGN blocks the event retry case");
    const retryVersion = await createVersion(left, { cap: "100.00", rewardType: "FIXED_COUPON", amount: "20.00" });
    await left.incentiveCampaign.updateMany({
      where: { name: PREFIX, id: { not: retryVersion.campaign.id } },
      data: { status: "PAUSED" },
    });
    const token = crypto.randomUUID();
    const event = await createEvent(left, "retry", {
      status: "PROCESSING",
      attempts: 1,
      claimToken: token,
    });
    const repository = createPrismaEventRepository(left);
    const flags = { issuance: true, promotional: true, referral: true, redemption: true };
    const failed = await evaluateClaimed(repository, event, {
      token,
      flags,
      now: new Date("2026-11-17T12:00:00.000Z"),
      actorId: "system",
      couponWriter: async () => {
        throw new Error("coupon failed once");
      },
    });
    assert(failed.status === "FAILED", "a coupon failure records the event for retry");
    assert(await left.incentiveReward.count({ where: { sourceEventId: event.id } }) === 0, "the failed attempt left a reward");
    const retryToken = crypto.randomUUID();
    await left.incentiveEvent.update({
      where: { id: event.id },
      data: { status: "PROCESSING", claimToken: retryToken },
    });
    const reloaded = await left.incentiveEvent.findUnique({ where: { id: event.id } });
    const retried = await evaluateClaimed(repository, reloaded, {
      token: retryToken,
      flags,
      now: new Date("2026-11-17T12:05:00.000Z"),
      actorId: "system",
      couponWriter: async () => ({ id: `${PREFIX}-coupon` }),
    });
    assert(retried.status === "PROCESSED", "the retry processes the event");
    const retriedRows = await left.incentiveReward.findMany({ where: { sourceEventId: event.id } });
    assert(retriedRows.length === 1 && retriedRows[0].couponId === `${PREFIX}-coupon`, "the retry issues one reward");

    const approvalVersion = await createVersion(left, { cap: "20.00", issued: "10.00", amount: "10.00" });
    const waiting = await left.incentiveReward.create({
      data: {
        campaignVersionId: approvalVersion.version.id,
        rewardSlot: "credit",
        recipientUserId: `${PREFIX}-user`,
        sourceEventId: `${PREFIX}-approval`,
        status: "PENDING_APPROVAL",
        amount: "10.00",
        idempotencyKey: `${PREFIX}-approval-key`,
      },
    });
    const existingSetting = await left.incentiveSetting.findUnique({ where: { key: "issuance_enabled" } });
    if (existingSetting && String(existingSetting.value).trim() === "true") {
      throw new Error("ISSUANCE_ALREADY_ENABLED");
    }
    let approvalCode = null;
    try {
      await left.$transaction((tx) => approveReward(tx, { rewardId: waiting.id, actorId: PREFIX }));
    } catch (error) {
      approvalCode = error.code;
    }
    if (!existingSetting) {
      assert(approvalCode === "ISSUANCE_DISABLED", "approval is refused when issuance is missing");
    }
    assert((await left.incentiveReward.findUnique({ where: { id: waiting.id } })).status === "PENDING_APPROVAL", "refused approval does not change the reward");
    assert(await left.incentiveLedgerEntry.count({ where: { rewardId: waiting.id } }) === 0, "refused approval writes no ledger entry");
    if (!existingSetting) {
      const beforeSettings = await left.incentiveSetting.count();
      let disabledCode = null;
      try {
        await left.$transaction(async (tx) => {
          await tx.incentiveSetting.create({ data: { key: "issuance_enabled", value: "false" } });
          await approveReward(tx, { rewardId: waiting.id, actorId: PREFIX });
        });
      } catch (error) {
        disabledCode = error.code;
      }
      assert(disabledCode === "ISSUANCE_DISABLED", "approval is refused when issuance is false");
      assert(await left.incentiveSetting.count() === beforeSettings, "the refused approval did not leave a setting row");
    }

    const once = await createVersion(left, { cap: "10.00", issued: "10.00", amount: "10.00" });
    const onceReward = await left.incentiveReward.create({
      data: {
        campaignVersionId: once.version.id,
        rewardSlot: "credit",
        recipientUserId: `${PREFIX}-user`,
        sourceEventId: `${PREFIX}-once`,
        status: "PENDING_APPROVAL",
        amount: "10.00",
        idempotencyKey: `${PREFIX}-once-key`,
      },
    });
    await Promise.all([
      left.$transaction((tx) => rejectReward(tx, { rewardId: onceReward.id, actorId: PREFIX })),
      right.$transaction((tx) => rejectReward(tx, { rewardId: onceReward.id, actorId: PREFIX })),
    ]);
    assert(await issuedAmount(left, once.version.id) === 0, "concurrent rejection releases the reservation once");

    const guardVersion = await createVersion(left, { cap: "100.00", amount: "5.00" });
    const guardReward = await left.incentiveReward.create({
      data: {
        campaignVersionId: guardVersion.version.id,
        rewardSlot: "guard",
        recipientUserId: `${PREFIX}-user`,
        sourceEventId: `${PREFIX}-guard`,
        status: "ISSUED",
        amount: "5.00",
        idempotencyKey: `${PREFIX}-guard-key`,
      },
    });
    await left.incentiveLedgerEntry.create({
      data: {
        rewardId: guardReward.id,
        entryType: "ISSUE",
        amount: "5.00",
        idempotencyKey: `${PREFIX}-guard-issue`,
      },
    });
    await expectReject(
      () => left.$transaction((tx) => tx.$executeRaw`
        UPDATE "IncentiveLedgerEntry" SET "reason" = 'changed' WHERE "rewardId" = ${guardReward.id}
      `),
      "append-only"
    );
    await expectReject(
      () => left.$transaction((tx) => tx.$executeRaw`
        DELETE FROM "IncentiveLedgerEntry" WHERE "rewardId" = ${guardReward.id}
      `),
      "append-only"
    );
    await expectReject(
      () => left.$transaction((tx) => tx.incentiveLedgerEntry.create({
        data: {
          rewardId: guardReward.id,
          entryType: "REDEEM",
          amount: "-6.00",
          idempotencyKey: `${PREFIX}-guard-negative`,
        },
      })),
      "would make the balance negative"
    );
    assert(await balance(left, guardReward.id) === 5, "a rejected debit leaves the committed balance");
    for (const attempt of [
      { entryType: "ISSUE", amount: "-1.00", key: "bad-issue", text: "ISSUE amount must be positive" },
      { entryType: "REDEEM", amount: "1.00", key: "bad-redeem", text: "REDEEM amount must be negative" },
      { entryType: "EXPIRE", amount: "1.00", key: "bad-expire", text: "EXPIRE amount must be negative" },
      { entryType: "ADJUST", amount: "1.00", key: "bad-adjust", text: "entry type is not supported" },
    ]) {
      await expectReject(
        () => left.$transaction((tx) => tx.incentiveLedgerEntry.create({
          data: {
            rewardId: guardReward.id,
            entryType: attempt.entryType,
            amount: attempt.amount,
            idempotencyKey: `${PREFIX}-${attempt.key}`,
          },
        })),
        attempt.text
      );
    }
    assert(await balance(left, guardReward.id) === 5, "rejected signs and types leave the committed balance");
  } catch (error) {
    failure = error;
  } finally {
    const cleanupErrors = [];
    if (started) {
      try {
        await removeOwned(left);
      } catch (error) {
        console.error("LEDGER_CLEANUP_FAILED");
        console.error(error);
        cleanupErrors.push(error);
      }
      try {
        await assertTriggersEnabled(left);
      } catch (error) {
        cleanupErrors.push(error);
      }
      const restorationFailed = cleanupErrors.some((error) => error && error.message === "LEDGER_TRIGGER_RESTORATION_FAILED");
      if (!restorationFailed) {
        try {
          await assertGone(left);
        } catch (error) {
          console.error("LEDGER_CLEANUP_ASSERT_FAILED");
          console.error(error);
          cleanupErrors.push(error);
        }
      }
    }
    await left.$disconnect().catch(() => {});
    await right.$disconnect().catch(() => {});
    if (cleanupErrors.length) {
      if (failure) console.error(failure);
      const restoration = cleanupErrors.find((error) => error && error.message === "LEDGER_TRIGGER_RESTORATION_FAILED");
      throw restoration || cleanupErrors[0];
    }
    if (failure) throw failure;
  }
  console.log("incentive rewards postgresql guard ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
