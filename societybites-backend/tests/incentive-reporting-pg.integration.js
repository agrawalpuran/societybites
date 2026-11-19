/**
 * Read-only reporting checks for the local foundation database.
 * Not part of npm test. Does not apply a migration and does not read .env.
 * The password is supplied by scripts/run-incentive-reporting-pg.ps1.
 * This file does not insert, update, or delete. A session read-only setting
 * rejects a write. Row counts are compared before and after the queries.
 * Queries that need User.id or User.name are not called when User is absent.
 */
const { Prisma, PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("../lib/prismaPool");
const { auditPage, performance, referralAnalytics, rewardReport, risk } = require("../modules/incentive-engine/analytics/query");
const { createPrismaEventRepository } = require("../modules/incentive-engine/events/repository");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_foundation";
const COUNTED = [
  "IncentiveCampaign",
  "IncentiveCampaignVersion",
  "IncentiveReferral",
  "IncentiveReferralCode",
  "IncentiveReward",
  "IncentiveRewardDefinition",
  "IncentiveBudget",
  "IncentiveLedgerEntry",
  "IncentiveApproval",
  "IncentiveAuditLog",
  "IncentiveEvent",
  "IncentiveSetting",
];
const PRODUCT_TABLES = ["User", "Order", "Listing", "SellerTermsAcceptance", "Coupon", "CouponEligibleUser"];
const NOW = new Date("2026-11-18T00:00:00.000Z");
const WEEK = { from: "2026-11-11T00:00:00.000Z", to: "2026-11-18T00:00:00.000Z" };
const DAY = { from: "2026-11-17T00:00:00.000Z", to: "2026-11-18T00:00:00.000Z" };
const ISSUED = ["ISSUED", "PARTIALLY_REDEEMED", "REDEEMED"];

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

async function regclass(prisma, name) {
  const rows = await prisma.$queryRaw`SELECT to_regclass(${`"${name}"`})::text AS name`;
  return rows[0].name;
}

async function counts(prisma) {
  const totals = {};
  for (const name of COUNTED) {
    const rows = await prisma.$queryRawUnsafe(`SELECT COUNT(*)::int AS total FROM "${name}"`);
    totals[name] = Number(rows[0].total);
  }
  return totals;
}

async function expectCode(work, code) {
  try {
    await work();
  } catch (error) {
    assert(error && error.code === code, `expected ${code}`);
    return;
  }
  throw new Error(`expected ${code}`);
}

function money(value) {
  return typeof value === "string" && /^\d+\.\d{2}$/.test(value);
}

async function referralDaily(prisma, campaignId) {
  return prisma.$queryRaw`
    SELECT to_char(date_trunc('day', "attributedAt"), 'YYYY-MM-DD') AS day,
           COUNT(*)::int AS attributed,
           COUNT(*) FILTER (WHERE status = 'QUALIFIED')::int AS qualified
    FROM "IncentiveReferral"
    WHERE "campaignId" = ${campaignId}
      AND "attributedAt" >= ${new Date(WEEK.from)}
      AND "attributedAt" < ${new Date(WEEK.to)}
    GROUP BY 1
    ORDER BY 1
  `;
}

async function rewardDaily(prisma, versionIds) {
  return prisma.$queryRaw`
    SELECT to_char(date_trunc('day', "createdAt"), 'YYYY-MM-DD') AS day,
           COUNT(*)::int AS issued
    FROM "IncentiveReward"
    WHERE "campaignVersionId" IN (${Prisma.join(versionIds)})
      AND status IN ('ISSUED', 'PARTIALLY_REDEEMED', 'REDEEMED')
      AND "createdAt" >= ${new Date(DAY.from)}
      AND "createdAt" < ${new Date(DAY.to)}
    GROUP BY 1
    ORDER BY 1
  `;
}

async function riskReadsUser(prisma, campaignId) {
  const campaign = await prisma.incentiveCampaign.findUnique({ where: { id: campaignId } });
  const version = campaign && campaign.currentVersionId
    ? await prisma.incentiveCampaignVersion.findUnique({ where: { id: campaign.currentVersionId } })
    : null;
  const limit = version && version.snapshot && version.snapshot.referralPolicy
    ? version.snapshot.referralPolicy.maxAttributionsPerReferrer
    : null;
  if (!Number.isInteger(limit) || limit <= 0) return false;
  const grouped = await prisma.incentiveReferral.groupBy({
    by: ["referrerUserId"],
    where: { campaignId },
    _count: { _all: true },
  });
  return grouped.some((row) => row._count._all >= Math.ceil(limit * 0.8));
}

async function main() {
  assertSafeUrl(process.env.DATABASE_URL);
  const prisma = localClient(process.env.DATABASE_URL);
  const blocked = [];
  try {
    const identity = await prisma.$queryRaw`SELECT current_database() AS database, inet_server_addr()::text AS address`;
    assert(identity[0].database === REQUIRED_DATABASE, "connected database is not the foundation database");
    assert(String(identity[0].address || "").startsWith(REQUIRED_HOST), "connected address is not loopback");
    await prisma.$queryRawUnsafe("SELECT set_config('default_transaction_read_only', 'on', false)");
    const mode = await prisma.$queryRaw`SELECT current_setting('default_transaction_read_only') AS mode`;
    assert(mode[0].mode === "on", "session is not read only");
    console.log(`connection ${REQUIRED_HOST}:${REQUIRED_PORT}/${REQUIRED_DATABASE}`);
    console.log("session default_transaction_read_only=on");

    const before = await counts(prisma);
    const present = {};
    for (const name of PRODUCT_TABLES) present[name] = Boolean(await regclass(prisma, name));
    for (const name of PRODUCT_TABLES) {
      console.log(`product table ${name} ${present[name] ? "present" : "absent"}`);
    }

    const campaign = await prisma.incentiveCampaign.findFirst({
      select: { id: true, currentVersionId: true },
      orderBy: { createdAt: "desc" },
    });
    const versions = campaign
      ? await prisma.incentiveCampaignVersion.findMany({ where: { campaignId: campaign.id }, select: { id: true } })
      : [];
    const campaignId = campaign ? campaign.id : "00000000-0000-0000-0000-000000000000";
    const referralSeries = await referralDaily(prisma, campaignId);
    assert(Array.isArray(referralSeries), "referral daily aggregation did not return rows");
    for (const row of referralSeries) assert(/^\d{4}-\d{2}-\d{2}$/.test(row.day), "referral day is not a date");
    console.log(`referral daily aggregation rows=${referralSeries.length}`);

    if (versions.length) {
      const rewardSeries = await rewardDaily(prisma, versions.map((row) => row.id));
      assert(Array.isArray(rewardSeries), "reward daily aggregation did not return rows");
      console.log(`reward daily aggregation rows=${rewardSeries.length}`);
    } else {
      console.log("reward daily aggregation skipped: the selected campaign has no versions");
    }

    if (campaign) {
      const full = await performance(prisma, { campaignId: campaign.id, query: WEEK, now: NOW });
      const oneDay = await performance(prisma, { campaignId: campaign.id, query: DAY, now: NOW });
      assert(full.series && oneDay.budget && money(full.budget.configured), "performance shape is incomplete");
      console.log(`performance executed series=${full.series.length} oneDayRewards=${oneDay.rewards.issued}`);
    } else {
      const created = { gte: new Date(WEEK.from), lt: new Date(WEEK.to) };
      const referralGroups = await prisma.incentiveReferral.groupBy({
        by: ["status"],
        where: { attributedAt: created },
        _count: { _all: true },
      });
      const rewardGroups = await prisma.incentiveReward.groupBy({
        by: ["status", "campaignVersionId", "rewardSlot"],
        where: { createdAt: created },
        _count: { _all: true },
      });
      const budgets = await prisma.incentiveBudget.findMany({ take: 20 });
      const timeline = await prisma.incentiveAuditLog.findMany({
        orderBy: { createdAt: "desc" },
        take: 50,
        select: { id: true, action: true, actorId: true, createdAt: true, before: true, after: true },
      });
      const pending = await prisma.incentiveReward.count({ where: { status: "PENDING_APPROVAL" } });
      assert(Array.isArray(referralGroups) && Array.isArray(rewardGroups) && Array.isArray(budgets), "performance aggregates failed");
      assert(Array.isArray(timeline) && Number.isInteger(pending), "performance timeline failed");
      console.log(`performance() not called: no campaign row. Aggregates ran directly groups=${referralGroups.length} rewards=${rewardGroups.length} pending=${pending}`);
    }
    await expectCode(
      () => auditPage(prisma, {
        query: { from: "2024-01-01T00:00:00.000Z", to: "2026-11-18T00:00:00.000Z" },
      }),
      "RANGE_TOO_WIDE",
    );
    await expectCode(
      () => auditPage(prisma, { query: { from: WEEK.to, to: WEEK.from } }),
      "RANGE_INVALID",
    );
    if (campaign) {
      await expectCode(
        () => performance(prisma, {
          campaignId: campaign.id,
          query: { from: "2024-01-01T00:00:00.000Z", to: "2026-11-18T00:00:00.000Z" },
          now: NOW,
        }),
        "RANGE_TOO_WIDE",
      );
    }
    console.log("date filters rejected a reversed range and a range over 366 days");

    const qualified = await prisma.incentiveReferral.count({ where: { status: "QUALIFIED" } });
    const created = { gte: new Date(WEEK.from), lt: new Date(WEEK.to) };
    if (present.User || qualified === 0) {
      const analytics = await referralAnalytics(prisma, { query: WEEK, now: NOW });
      assert(analytics.funnel && typeof analytics.funnel.codesGenerated === "number", "referral analytics did not aggregate");
      if (campaign) {
        const scoped = await referralAnalytics(prisma, { query: { ...WEEK, campaignId: campaign.id }, now: NOW });
        assert(scoped.campaignId === campaign.id, "campaign filter was not applied");
      }
      console.log(`referral analytics executed qualifiedRows=${qualified}`);
      if (!present.User) {
        blocked.push("leaderboard name lookup reads User.id and User.name. It was not called because no QUALIFIED referral exists. User is absent.");
      }
    } else {
      const codes = await prisma.incentiveReferralCode.count({ where: { createdAt: created } });
      const byKind = await prisma.incentiveReferral.groupBy({
        by: ["acquisitionKind", "status"],
        where: { attributedAt: created },
        _count: { _all: true },
      });
      const approved = await prisma.incentiveApproval.count({ where: { decision: "APPROVED", createdAt: created } });
      const issued = await prisma.incentiveReward.count({ where: { status: { in: ISSUED }, createdAt: created } });
      assert(Number.isInteger(codes) && Array.isArray(byKind) && Number.isInteger(approved) && Number.isInteger(issued), "referral aggregates failed");
      console.log(`referral analytics incentive tables executed codes=${codes} groups=${byKind.length}`);
      blocked.push("referralAnalytics and leaderboard were not called. They read User.id and User.name when a QUALIFIED referral exists, and User is absent.");
    }

    const failures = await risk(prisma, { query: WEEK, now: NOW });
    assert(Array.isArray(failures.indicators), "failure aggregation did not return indicators");
    console.log(`failure reason aggregation indicators=${failures.indicators.length}`);
    if (campaign && !present.User && await riskReadsUser(prisma, campaign.id)) {
      blocked.push("risk approaching-cap name lookup reads User.id and User.name. A referrer is at the cap threshold and User is absent, so risk() was not called with that campaign.");
    } else if (campaign) {
      const scopedRisk = await risk(prisma, { query: { ...WEEK, campaignId: campaign.id }, now: NOW });
      assert(scopedRisk.indicators.length >= 2, "campaign risk shape is incomplete");
      console.log("risk campaign scope executed");
      if (!present.User) {
        blocked.push("risk name lookup reads User.id and User.name. No referrer reached the cap threshold, so prisma.user.findMany was not called. User is absent.");
      }
    }

    const rewards = await rewardReport(prisma, { query: WEEK, now: NOW });
    const issuedOnly = await rewardReport(prisma, { query: { ...WEEK, status: "ISSUED", rewardType: "PROMOTIONAL_CREDIT" }, now: NOW });
    assert(money(rewards.balances.promotionalCredit) && money(rewards.balances.points), "ledger balances were not aggregated");
    assert(rewards.balances.withdrawable === false, "credit balance was marked withdrawable");
    assert(Array.isArray(issuedOnly.timeline), "filtered reward report has no timeline");
    console.log(`reward report executed timeline=${rewards.timeline.length} exhausted=${rewards.exceptions.budgetExhausted}`);
    if (rewards.nextCursor) {
      const next = await rewardReport(prisma, { query: { ...WEEK, cursor: rewards.nextCursor }, now: NOW });
      assert(!next.timeline.some((row) => row.id === rewards.nextCursor), "reward cursor repeated the cursor row");
      console.log(`reward timeline next page rows=${next.timeline.length}`);
    } else if (rewards.timeline.length) {
      const lastId = rewards.timeline[rewards.timeline.length - 1].id;
      const next = await rewardReport(prisma, { query: { ...WEEK, cursor: lastId }, now: NOW });
      assert(!next.timeline.some((row) => row.id === lastId), "reward cursor repeated the last row");
      console.log(`reward timeline cursor page rows=${next.timeline.length}`);
    } else {
      const absent = await rewardReport(prisma, { query: { ...WEEK, cursor: "reporting-cursor-absent" }, now: NOW });
      assert(absent.timeline.length === 0, "an unknown reward cursor changed an empty page");
      console.log("reward timeline cursor tested on an empty page");
    }

    const audits = await auditPage(prisma, { query: { ...WEEK, action: "REWARD_APPROVED" } });
    assert(audits.entries.every((row) => row.action === "REWARD_APPROVED"), "audit action filter was not applied");
    assert(audits.entries.length <= 20, "audit page exceeded 20 rows");
    console.log(`audit page executed rows=${audits.entries.length}`);
    if (audits.nextCursor) {
      const next = await auditPage(prisma, { query: { ...WEEK, action: "REWARD_APPROVED", cursor: audits.nextCursor } });
      assert(!next.entries.some((row) => row.id === audits.nextCursor), "audit cursor repeated the cursor row");
      console.log(`audit next page rows=${next.entries.length}`);
    } else {
      const cursor = audits.entries.length ? audits.entries[audits.entries.length - 1].id : "reporting-cursor-absent";
      const next = await auditPage(prisma, { query: { ...WEEK, action: "REWARD_APPROVED", cursor } });
      assert(!next.entries.some((row) => row.id === cursor), "audit cursor repeated the last row");
      console.log(`audit cursor page rows=${next.entries.length}`);
    }

    const repository = createPrismaEventRepository(prisma);
    const monitored = await repository.listEvents({ limit: 2 });
    const byStatus = await repository.listEvents({ status: "PROCESSED", limit: 2 });
    const byType = await repository.listEvents({ type: "ORDER_QUALIFIED", limit: 2 });
    assert(Array.isArray(monitored) && Array.isArray(byStatus) && Array.isArray(byType), "event monitoring did not return rows");
    assert(byStatus.every((row) => row.status === "PROCESSED"), "event status filter was not applied");
    assert(byType.every((row) => row.type === "ORDER_QUALIFIED"), "event type filter was not applied");
    const reconciliation = await repository.findReconciliation(NOW, 60 * 60 * 1000);
    assert(reconciliation && Array.isArray(reconciliation.dead) && Array.isArray(reconciliation.failedDue), "event reconciliation did not return rows");
    console.log(`event monitoring rows=${monitored.length} processed=${byStatus.length} orderQualified=${byType.length} dead=${reconciliation.dead.length}`);
    if (monitored.length) {
      const next = await repository.listEvents({ cursor: monitored[monitored.length - 1].id, limit: 2 });
      assert(!next.some((row) => row.id === monitored[monitored.length - 1].id), "event cursor repeated the cursor row");
      console.log(`event cursor page rows=${next.length}`);
    } else {
      const next = await repository.listEvents({ cursor: "reporting-cursor-absent", limit: 2 });
      assert(next.length === 0, "an unknown event cursor changed an empty page");
      console.log("event cursor tested on an empty page");
    }

    const after = await counts(prisma);
    assert(JSON.stringify(before) === JSON.stringify(after), "a read-only reporting query changed a row count");
    console.log("row counts unchanged");
    for (const line of blocked) console.log(`BLOCKED ${line}`);
    console.log("incentive reporting postgresql read ok");
  } finally {
    await prisma.$disconnect().catch(() => {});
  }
}

main().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});
