/**
 * Phase 3A PostgreSQL harness for coupon issuance and concurrent approval.
 * Not part of npm test. Do not run it until execution is explicitly approved.
 * The runner must set DATABASE_URL before Node starts. This file checks that
 * URL before loading the reward code, so a missing or rejected URL does not
 * load .env. It never starts the API and never applies a migration.
 *
 * Target: 127.0.0.1:5432/societybites_incentive_integration_v2
 * Every inserted row uses this run's prefix. Cleanup deletes only those rows.
 * Ledger triggers are disabled only inside the cleanup transaction and enabled
 * again before that transaction commits.
 * A session advisory lock on the first client blocks a second run. The second
 * client never takes that lock. The lock is released before disconnect.
 */
const crypto = require("crypto");
const { PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("../lib/prismaPool");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_integration_v2";
const PREFIX = `p3${crypto.randomBytes(6).toString("hex")}`;
const FIXED_NOW = new Date("2026-11-17T12:00:00.000Z");
const LEDGER_TRIGGERS = [
  "incentive_ledger_no_update",
  "incentive_ledger_no_delete",
  "incentive_ledger_guard_insert",
];
const HARNESS_LOCK_A = 872341;
const HARNESS_LOCK_B = 230611;

function assert(condition, message) {
  if (!condition) throw new Error(message);
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
  bounded.searchParams.set("connection_limit", "1");
  return new PrismaClient({ datasources: { db: { url: bounded.toString() } } });
}

function asNumber(value) {
  return Number(String(value));
}

function enabledValue(value) {
  return typeof value === "string"
    && value.replace(/^[ \t\n\r\f\v]+/, "").replace(/[ \t\n\r\f\v]+$/, "") === "true";
}

function snapshotBody(slot, amount, rewardType, extra = {}) {
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
      usageLimit: 1,
      ...extra,
    }],
    budget: { amountCap: "100.00", currency: "INR" },
  };
}

function issueInput(version, event, body) {
  return {
    event: {
      id: event.id,
      type: event.type,
      userId: event.userId,
      entityId: event.entityId,
    },
    matches: [{ campaignId: version.campaignId, passed: true }],
    campaigns: [{
      id: version.campaignId,
      stackingMode: "STACK",
      priority: 1,
      version: { id: version.id, snapshot: body },
    }],
    flags: { issuance: true },
    now: FIXED_NOW,
  };
}

async function assertIdentity(prisma) {
  const rows = await prisma.$queryRaw`
    SELECT current_database() AS database_name,
           host(inet_server_addr()) AS server_host,
           inet_server_port()::int AS server_port
  `;
  const row = rows[0];
  assert(row.database_name === REQUIRED_DATABASE, "connected database is not the v2 integration database");
  assert(row.server_host === REQUIRED_HOST, "connected host is not loopback");
  assert(Number(row.server_port) === Number(REQUIRED_PORT), "connected port is not 5432");
}

async function assertTriggersEnabled(prisma) {
  const triggers = await prisma.$queryRaw`
    SELECT tgname, tgenabled::text AS state
    FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgrelid = '"IncentiveLedgerEntry"'::regclass
      AND tgname IN ('incentive_ledger_no_update', 'incentive_ledger_no_delete', 'incentive_ledger_guard_insert')
  `;
  const states = new Map(triggers.map((row) => [row.tgname, row.state]));
  const enabled = LEDGER_TRIGGERS.every((name) => states.get(name) === "O");
  assert(triggers.length === LEDGER_TRIGGERS.length && enabled, "ledger triggers are missing or not enabled");
}

async function assertFlagsOff(prisma) {
  const rows = await prisma.incentiveSetting.findMany();
  assert(rows.length === 0, "IncentiveSetting already has rows; refusing to change flags");
  assert(rows.every((row) => !enabledValue(row.value)), "an incentive flag is already enabled");
}

async function sessionPid(prisma) {
  const rows = await prisma.$queryRaw`SELECT pg_backend_pid()::int AS pid`;
  return Number(rows[0].pid);
}

async function tryHarnessLock(prisma) {
  const rows = await prisma.$queryRaw`
    SELECT pg_try_advisory_lock(${HARNESS_LOCK_A}::integer, ${HARNESS_LOCK_B}::integer) AS locked
  `;
  return rows[0].locked === true;
}

async function releaseHarnessLock(prisma) {
  const rows = await prisma.$queryRaw`
    SELECT pg_advisory_unlock(${HARNESS_LOCK_A}::integer, ${HARNESS_LOCK_B}::integer) AS released
  `;
  return rows[0].released === true;
}

async function baselineCounts(prisma) {
  const [
    users,
    coupons,
    eligibleUsers,
    campaigns,
    versions,
    budgets,
    events,
    settings,
    rewards,
    ledger,
    approvals,
    audits,
    redemptions,
  ] = await Promise.all([
    prisma.user.count(),
    prisma.coupon.count(),
    prisma.couponEligibleUser.count(),
    prisma.incentiveCampaign.count(),
    prisma.incentiveCampaignVersion.count(),
    prisma.incentiveBudget.count(),
    prisma.incentiveEvent.count(),
    prisma.incentiveSetting.count(),
    prisma.incentiveReward.count(),
    prisma.incentiveLedgerEntry.count(),
    prisma.incentiveApproval.count(),
    prisma.incentiveAuditLog.count(),
    prisma.incentiveRedemption.count(),
  ]);
  return {
    users,
    coupons,
    eligibleUsers,
    campaigns,
    versions,
    budgets,
    events,
    settings,
    rewards,
    ledger,
    approvals,
    audits,
    redemptions,
  };
}

async function createUser(prisma) {
  return prisma.user.create({
    data: { phone: PREFIX, name: PREFIX, role: "buyer" },
  });
}

async function createVersion(prisma, body) {
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
      publishedAt: FIXED_NOW,
    },
  });
  await prisma.incentiveCampaign.update({
    where: { id: campaign.id },
    data: { currentVersionId: version.id },
  });
  await prisma.incentiveBudget.create({
    data: { versionId: version.id, amountCap: "100.00", issuedAmount: "0.00", currency: "INR" },
  });
  return { campaign, version, body };
}

async function createEvent(prisma, suffix, userId) {
  return prisma.incentiveEvent.create({
    data: {
      eventId: `${PREFIX}-${suffix}`,
      type: "USER_REGISTERED",
      entityType: "user",
      entityId: userId,
      userId,
      occurredAt: FIXED_NOW,
      payload: {},
      status: "PROCESSED",
    },
  });
}

async function budgetAmount(prisma, versionId) {
  const budget = await prisma.incentiveBudget.findUnique({ where: { versionId } });
  assert(budget, "budget row is missing");
  return asNumber(budget.issuedAmount);
}

async function removeOwned(prisma, state) {
  await prisma.$transaction(async (tx) => {
    await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" DISABLE TRIGGER USER`;
    try {
      await tx.$executeRaw`
        DELETE FROM "Coupon" AS coupon
        WHERE coupon."id" IN (
          SELECT reward."couponId"
          FROM "IncentiveReward" AS reward
          JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
          JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
          WHERE campaign."name" = ${PREFIX}
            AND reward."couponId" IS NOT NULL
        )
      `;
      if (state.userId) {
        await tx.$executeRaw`
          DELETE FROM "Coupon" AS coupon
          WHERE coupon."id" IN (
            SELECT eligible."couponId"
            FROM "CouponEligibleUser" AS eligible
            WHERE eligible."userId" = ${state.userId}
          )
        `;
      }
      await tx.$executeRaw`
        DELETE FROM "IncentiveLedgerEntry"
        WHERE "rewardId" IN (
          SELECT reward."id"
          FROM "IncentiveReward" AS reward
          JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
          JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
          WHERE campaign."name" = ${PREFIX}
        )
      `;
      await tx.$executeRaw`
        DELETE FROM "IncentiveRedemption"
        WHERE "rewardId" IN (
          SELECT reward."id"
          FROM "IncentiveReward" AS reward
          JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
          JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
          WHERE campaign."name" = ${PREFIX}
        )
      `;
      await tx.$executeRaw`
        DELETE FROM "IncentiveApproval"
        WHERE "rewardId" IN (
          SELECT reward."id"
          FROM "IncentiveReward" AS reward
          JOIN "IncentiveCampaignVersion" AS version ON version."id" = reward."campaignVersionId"
          JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
          WHERE campaign."name" = ${PREFIX}
        )
      `;
      await tx.$executeRaw`
        DELETE FROM "IncentiveReward" AS reward
        USING "IncentiveCampaignVersion" AS version, "IncentiveCampaign" AS campaign
        WHERE reward."campaignVersionId" = version."id"
          AND version."campaignId" = campaign."id"
          AND campaign."name" = ${PREFIX}
      `;
      await tx.$executeRaw`
        DELETE FROM "IncentiveAuditLog"
        WHERE "actorId" = ${PREFIX}
           OR "incentiveEventId" IN (
             SELECT "id" FROM "IncentiveEvent" WHERE "eventId" LIKE ${`${PREFIX}-%`}
           )
           OR "campaignId" IN (
             SELECT "id" FROM "IncentiveCampaign" WHERE "name" = ${PREFIX}
           )
      `;
      await tx.$executeRaw`DELETE FROM "IncentiveEvent" WHERE "eventId" LIKE ${`${PREFIX}-%`}`;
      await tx.$executeRaw`
        DELETE FROM "IncentiveBudget"
        WHERE "versionId" IN (
          SELECT version."id"
          FROM "IncentiveCampaignVersion" AS version
          JOIN "IncentiveCampaign" AS campaign ON campaign."id" = version."campaignId"
          WHERE campaign."name" = ${PREFIX}
        )
      `;
      await tx.$executeRaw`
        DELETE FROM "IncentiveCampaignVersion"
        WHERE "campaignId" IN (SELECT "id" FROM "IncentiveCampaign" WHERE "name" = ${PREFIX})
      `;
      await tx.$executeRaw`DELETE FROM "IncentiveCampaign" WHERE "name" = ${PREFIX}`;
      if (state.userId) {
        await tx.$executeRaw`
          DELETE FROM "User"
          WHERE "id" = ${state.userId}
            AND "phone" = ${PREFIX}
        `;
      }
      if (state.createdSetting) {
        await tx.$executeRaw`
          DELETE FROM "IncentiveSetting"
          WHERE "key" = 'issuance_enabled'
        `;
      }
    } finally {
      await tx.$executeRaw`ALTER TABLE "IncentiveLedgerEntry" ENABLE TRIGGER USER`;
    }
  });
}

async function assertRestored(prisma, baseline, state) {
  await assertTriggersEnabled(prisma);
  const counts = await baselineCounts(prisma);
  assert(counts.users === baseline.users, "user count changed outside this run");
  assert(counts.coupons === baseline.coupons, "coupon count changed outside this run");
  assert(counts.eligibleUsers === baseline.eligibleUsers, "coupon eligibility count changed outside this run");
  assert(counts.campaigns === baseline.campaigns, "campaign count changed outside this run");
  assert(counts.versions === baseline.versions, "campaign version count changed outside this run");
  assert(counts.budgets === baseline.budgets, "budget count changed outside this run");
  assert(counts.events === baseline.events, "event count changed outside this run");
  assert(counts.settings === baseline.settings, "incentive setting count changed outside this run");
  assert(counts.rewards === baseline.rewards, "reward count changed outside this run");
  assert(counts.ledger === baseline.ledger, "ledger count changed outside this run");
  assert(counts.approvals === baseline.approvals, "approval count changed outside this run");
  assert(counts.audits === baseline.audits, "audit count changed outside this run");
  assert(counts.redemptions === baseline.redemptions, "redemption count changed outside this run");
  assert(await prisma.incentiveCampaign.count({ where: { name: PREFIX } }) === 0, "prefixed campaigns remain");
  assert(await prisma.incentiveEvent.count({ where: { eventId: { startsWith: `${PREFIX}-` } } }) === 0, "prefixed events remain");
  assert(await prisma.user.count({ where: { phone: PREFIX } }) === 0, "prefixed user remains");
  if (state.createdSetting) {
    assert(await prisma.incentiveSetting.count({ where: { key: "issuance_enabled" } }) === 0, "temporary issuance setting remains");
  }
}

async function assertCouponShape(prisma, reward, userId, couponCodeFor) {
  assert(reward.couponId, "issued coupon reward has no coupon id");
  const coupon = await prisma.coupon.findUnique({
    where: { id: reward.couponId },
    include: { eligibleUsers: true },
  });
  assert(coupon, "coupon row is missing");
  assert(coupon.code === couponCodeFor(reward.idempotencyKey), "coupon code does not match the reward idempotency key");
  assert(coupon.name === "SocietyEats reward", "coupon name");
  assert(coupon.discountType === "FIXED", "coupon discount type");
  assert(asNumber(coupon.discountValue) === 20, "coupon discount value");
  assert(coupon.maximumDiscount == null, "fixed coupon stored a maximum discount");
  assert(asNumber(coupon.minimumOrderValue) === 0, "coupon minimum order");
  assert(coupon.audienceType === "SELECTED_USERS", "coupon audience");
  assert(coupon.status === "ACTIVE", "coupon status");
  assert(coupon.fundedBy === "SOCIETYEATS", "coupon funding");
  assert(coupon.totalUsageLimit === 1 && coupon.usagePerBuyerLimit === 1, "coupon usage limits");
  assert(coupon.validFrom.getTime() === FIXED_NOW.getTime(), "coupon valid from");
  assert(coupon.validUntil.getTime() === reward.expiresAt.getTime(), "coupon valid until");
  assert(coupon.eligibleUsers.length === 1 && coupon.eligibleUsers[0].userId === userId, "coupon eligible user");
  assert(await prisma.incentiveLedgerEntry.count({ where: { rewardId: reward.id } }) === 0, "coupon reward wrote a ledger entry");
}

async function main() {
  assertSafeUrl(process.env.DATABASE_URL);
  const { couponCodeFor, rewardKey, issueMatchedRewards } = require("../modules/incentive-engine/rewards/issue");
  const { approveReward } = require("../modules/incentive-engine/rewards/approve");
  const left = localClient(process.env.DATABASE_URL);
  const right = localClient(process.env.DATABASE_URL);
  const state = { userId: null, createdSetting: false };
  let started = false;
  let baseline = null;
  let failure = null;
  let lockHeld = false;
  let lockPid = null;
  try {
    await assertIdentity(left);
    await assertIdentity(right);
    const leftPid = await sessionPid(left);
    const rightPid = await sessionPid(right);
    assert(leftPid !== rightPid, "the two clients must be different PostgreSQL sessions");
    await assertTriggersEnabled(left);
    await assertFlagsOff(left);
    if (!await tryHarnessLock(left)) {
      throw new Error("another incentive rewards v2 run holds the harness lock");
    }
    lockHeld = true;
    lockPid = await sessionPid(left);
    assert(lockPid === leftPid, "the harness lock is not held by the first session");
    baseline = await baselineCounts(left);
    started = true;

    const user = await createUser(left);
    state.userId = user.id;

    const successBody = snapshotBody("coupon", "20.00", "FIXED_COUPON");
    const success = await createVersion(left, successBody);
    const successEvent = await createEvent(left, "success", user.id);
    const issued = await left.$transaction((tx) => issueMatchedRewards(tx, issueInput(success.version, successEvent, successBody)));
    assert(issued.issued.length === 1 && issued.pending.length === 0, "successful coupon issuance did not return one issued reward");
    const successReward = await left.incentiveReward.findUnique({ where: { id: issued.issued[0].id } });
    assert(successReward.status === "ISSUED", "successful coupon reward is not issued");
    assert(successReward.recipientUserId === user.id, "successful coupon recipient");
    assert(successReward.idempotencyKey === rewardKey(success.version.id, successEvent.id, user.id, "coupon"), "successful coupon idempotency key");
    await assertCouponShape(left, successReward, user.id, couponCodeFor);
    assert(await budgetAmount(left, success.version.id) === 20, "successful coupon budget charge");
    assert(await left.incentiveAuditLog.count({
      where: { campaignId: success.campaign.id, action: "REWARD_ISSUED" },
    }) === 1, "successful coupon audit");

    const rollbackBody = snapshotBody("coupon-rollback", "20.00", "FIXED_COUPON");
    const rollback = await createVersion(left, rollbackBody);
    const rollbackEvent = await createEvent(left, "rollback", user.id);
    const rollbackCode = couponCodeFor(rewardKey(rollback.version.id, rollbackEvent.id, user.id, "coupon-rollback"));
    const beforeRollback = {
      rewards: await left.incentiveReward.count({ where: { sourceEventId: rollbackEvent.id } }),
      budget: await budgetAmount(left, rollback.version.id),
      coupons: await left.coupon.count({ where: { code: rollbackCode } }),
      ledger: await left.incentiveLedgerEntry.count({ where: { idempotencyKey: { contains: rollbackEvent.id } } }),
      audits: await left.incentiveAuditLog.count({ where: { campaignId: rollback.campaign.id } }),
    };
    let rollbackError = null;
    try {
      await left.$transaction(async (tx) => {
        const saved = await issueMatchedRewards(tx, issueInput(rollback.version, rollbackEvent, rollbackBody));
        assert(saved.issued.length === 1 && saved.issued[0].couponId, "coupon reward was not created before rollback");
        throw new Error("ROLLBACK_COUPON");
      });
    } catch (error) {
      if (!error || error.message !== "ROLLBACK_COUPON") throw error;
      rollbackError = error;
    }
    assert(rollbackError, "coupon issuance must enter the transaction and then roll back");
    assert(await left.incentiveReward.count({ where: { sourceEventId: rollbackEvent.id } }) === beforeRollback.rewards, "rolled-back coupon left a reward");
    assert(await budgetAmount(left, rollback.version.id) === beforeRollback.budget, "rolled-back coupon left a budget charge");
    assert(await left.coupon.count({ where: { code: rollbackCode } }) === beforeRollback.coupons, "rolled-back coupon row remains");
    assert(await left.couponEligibleUser.count({ where: { userId: user.id, coupon: { code: rollbackCode } } }) === 0, "rolled-back coupon eligibility remains");
    assert(await left.incentiveLedgerEntry.count({ where: { idempotencyKey: { contains: rollbackEvent.id } } }) === beforeRollback.ledger, "rolled-back coupon left a ledger entry");
    assert(await left.incentiveAuditLog.count({ where: { campaignId: rollback.campaign.id } }) === beforeRollback.audits, "rolled-back coupon left an audit");

    const missingId = `${PREFIX}-missing`;
    const missingBody = snapshotBody("coupon-missing", "20.00", "FIXED_COUPON");
    const missing = await createVersion(left, missingBody);
    const missingEvent = await createEvent(left, "missing", missingId);
    const missingCode = couponCodeFor(rewardKey(missing.version.id, missingEvent.id, missingId, "coupon-missing"));
    let missingError = null;
    try {
      await left.$transaction((tx) => issueMatchedRewards(tx, issueInput(missing.version, missingEvent, missingBody)));
    } catch (error) {
      if (!error || error.code !== "P2003") throw error;
      missingError = error;
    }
    assert(missingError, "missing user must fail the coupon eligibility foreign key");
    assert(await left.incentiveReward.count({ where: { sourceEventId: missingEvent.id } }) === 0, "missing-user failure left a reward");
    assert(await budgetAmount(left, missing.version.id) === 0, "missing-user failure left a budget charge");
    assert(await left.coupon.count({ where: { code: missingCode } }) === 0, "missing-user failure left a coupon");
    assert(await left.couponEligibleUser.count({ where: { userId: missingId } }) === 0, "missing-user failure left an eligibility row");
    assert(await left.incentiveLedgerEntry.count({ where: { idempotencyKey: { contains: missingEvent.id } } }) === 0, "missing-user failure left a ledger entry");
    assert(await left.incentiveAuditLog.count({ where: { campaignId: missing.campaign.id } }) === 0, "missing-user failure left an audit");

    const repeatBody = snapshotBody("coupon-repeat", "20.00", "FIXED_COUPON");
    const repeat = await createVersion(left, repeatBody);
    const repeatEvent = await createEvent(left, "repeat", user.id);
    const repeatInput = issueInput(repeat.version, repeatEvent, repeatBody);
    const first = await left.$transaction((tx) => issueMatchedRewards(tx, repeatInput));
    const second = await left.$transaction((tx) => issueMatchedRewards(tx, repeatInput));
    assert(first.issued.length === 1 && second.issued.length === 1, "repeated coupon event did not return the issued reward");
    assert(first.issued[0].id === second.issued[0].id, "repeated coupon event returned a different reward");
    assert(await left.incentiveReward.count({ where: { sourceEventId: repeatEvent.id } }) === 1, "repeated coupon event created a second reward");
    const repeatReward = await left.incentiveReward.findUnique({ where: { id: first.issued[0].id } });
    await assertCouponShape(left, repeatReward, user.id, couponCodeFor);
    assert(await left.coupon.count({ where: { id: repeatReward.couponId } }) === 1, "repeated coupon event created another coupon row");
    assert(await left.couponEligibleUser.count({ where: { couponId: repeatReward.couponId } }) === 1, "repeated coupon event created another eligible user");
    assert(await left.couponEligibleUser.count({ where: { userId: user.id } }) === 2, "this run should own the successful coupon and the idempotent coupon");
    assert(await budgetAmount(left, repeat.version.id) === 20, "repeated coupon event charged the budget twice");

    const creditBody = snapshotBody("credit", "10.00", "PROMOTIONAL_CREDIT", { requireAdminApproval: true });
    const credit = await createVersion(left, creditBody);
    const creditEvent = await createEvent(left, "approval", user.id);
    const pending = await left.$transaction((tx) => issueMatchedRewards(tx, issueInput(credit.version, creditEvent, creditBody)));
    assert(pending.pending.length === 1 && pending.issued.length === 0, "approval fixture did not create one pending reward");
    const pendingReward = await left.incentiveReward.findUnique({ where: { id: pending.pending[0].id } });
    assert(pendingReward.status === "PENDING_APPROVAL" && pendingReward.couponId == null, "pending credit was issued early");
    assert(await budgetAmount(left, credit.version.id) === 10, "pending credit did not reserve the budget once");
    assert(await left.incentiveLedgerEntry.count({ where: { rewardId: pendingReward.id } }) === 0, "pending credit wrote a ledger entry");
    await assertFlagsOff(left);
    await left.incentiveSetting.create({ data: { key: "issuance_enabled", value: "true" } });
    state.createdSetting = true;
    assert((await sessionPid(left)) !== (await sessionPid(right)), "approval sessions are no longer distinct");
    const approvals = await Promise.allSettled([
      left.$transaction((tx) => approveReward(tx, { rewardId: pendingReward.id, actorId: PREFIX })),
      right.$transaction((tx) => approveReward(tx, { rewardId: pendingReward.id, actorId: PREFIX })),
    ]);
    assert(approvals.every((row) => row.status === "fulfilled"), "one concurrent approval session failed");
    assert(approvals.every((row) => row.value && row.value.id === pendingReward.id && row.value.status === "ISSUED"), "concurrent approval did not settle on the issued reward");
    const approved = await left.incentiveReward.findUnique({ where: { id: pendingReward.id } });
    assert(approved.status === "ISSUED" && approved.couponId == null, "approved credit reward status");
    assert(await budgetAmount(left, credit.version.id) === 10, "concurrent approval changed the reserved budget");
    const ledger = await left.incentiveLedgerEntry.findMany({ where: { rewardId: pendingReward.id } });
    assert(ledger.length === 1, "concurrent approval did not leave exactly one ledger entry");
    assert(ledger[0].entryType === "ISSUE" && asNumber(ledger[0].amount) === 10, "credit ledger issue amount");
    assert(ledger[0].idempotencyKey === `ISSUE:${pendingReward.idempotencyKey}`, "credit ledger idempotency key");
    const approvalRows = await left.incentiveApproval.findMany({ where: { rewardId: pendingReward.id } });
    assert(approvalRows.length === 1 && approvalRows[0].decision === "APPROVED" && approvalRows[0].decidedBy === PREFIX, "concurrent approval did not leave one approval");
    assert(await left.incentiveAuditLog.count({
      where: { actorId: PREFIX, action: "REWARD_APPROVED" },
    }) === 1, "concurrent approval did not leave one approval audit");
    assert(await left.incentiveAuditLog.count({
      where: { campaignId: credit.campaign.id, action: "REWARD_PENDING" },
    }) === 1, "pending credit audit");
    const storedFlag = await left.incentiveSetting.findUnique({ where: { key: "issuance_enabled" } });
    assert(storedFlag && storedFlag.value === "true", "temporary issuance setting changed before cleanup");
    assert(await left.incentiveSetting.count() === 1, "approval test wrote an unexpected setting");
  } catch (error) {
    failure = error;
  } finally {
    const cleanupErrors = [];
    if (started) {
      try {
        await removeOwned(left, state);
      } catch (error) {
        console.error("LEDGER_CLEANUP_FAILED");
        console.error(error);
        cleanupErrors.push(error);
      }
      try {
        await assertRestored(left, baseline, state);
      } catch (error) {
        console.error("LEDGER_CLEANUP_ASSERT_FAILED");
        console.error(error);
        cleanupErrors.push(error);
      }
    }
    if (lockHeld) {
      try {
        const pid = await sessionPid(left);
        if (lockPid != null && pid !== lockPid) {
          const error = new Error("HARNESS_LOCK_SESSION_CHANGED");
          console.error(error.message);
          cleanupErrors.push(error);
        } else if (!await releaseHarnessLock(left)) {
          const error = new Error("HARNESS_LOCK_RELEASE_FAILED");
          console.error(error.message);
          cleanupErrors.push(error);
        } else {
          lockHeld = false;
        }
      } catch (error) {
        console.error("HARNESS_LOCK_RELEASE_FAILED");
        console.error(error);
        cleanupErrors.push(error);
      }
    }
    await left.$disconnect().catch(() => {});
    await right.$disconnect().catch(() => {});
    if (cleanupErrors.length) {
      if (failure) console.error(failure);
      throw cleanupErrors[0];
    }
    if (failure) throw failure;
  }
  console.log("incentive rewards v2 integration ok");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
