/**
 * Local PostgreSQL checks for referral attribution.
 * Not part of npm test, test:unit, or test:regression.
 * Run only after the referral migrations are applied to
 * 127.0.0.1:5432/societybites_incentive_foundation and that database is empty.
 * Does not read .env. Does not issue rewards or touch Supabase.
 * The foundation database has no User or Order table, so this file does not
 * call registration, checkout, or payment code.
 */
const crypto = require("crypto");
const { PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("../lib/prismaPool");
const { createPrismaEventRepository } = require("../modules/incentive-engine/events/repository");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_foundation";
const PREFIX = `p2d${crypto.randomBytes(6).toString("hex")}`;
const TABLES = [
  ["IncentiveSetting", "incentiveSetting"],
  ["IncentiveCampaign", "incentiveCampaign"],
  ["IncentiveCampaignVersion", "incentiveCampaignVersion"],
  ["IncentiveAudience", "incentiveAudience"],
  ["IncentiveTrigger", "incentiveTrigger"],
  ["IncentiveRule", "incentiveRule"],
  ["IncentiveRewardDefinition", "incentiveRewardDefinition"],
  ["IncentiveBudget", "incentiveBudget"],
  ["IncentiveEvent", "incentiveEvent"],
  ["IncentiveReferralCode", "incentiveReferralCode"],
  ["IncentiveReferral", "incentiveReferral"],
  ["IncentiveReward", "incentiveReward"],
  ["IncentiveLedgerEntry", "incentiveLedgerEntry"],
  ["IncentiveRedemption", "incentiveRedemption"],
  ["IncentiveRiskEvaluation", "incentiveRiskEvaluation"],
  ["IncentiveApproval", "incentiveApproval"],
  ["IncentiveAuditLog", "incentiveAuditLog"],
];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertSafeUrl(label, value) {
  if (!value || typeof value !== "string") throw new Error(`${label} must be set before this test starts`);
  const lowered = value.toLowerCase();
  if (lowered.includes("supabase") || lowered.includes("pooler.supabase")) {
    throw new Error(`${label} must not point at Supabase`);
  }
  const parsed = new URL(value);
  const database = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  if (parsed.hostname !== REQUIRED_HOST) throw new Error(`${label} host must be ${REQUIRED_HOST}`);
  if ((parsed.port || REQUIRED_PORT) !== REQUIRED_PORT) throw new Error(`${label} port must be ${REQUIRED_PORT}`);
  if (database !== REQUIRED_DATABASE) throw new Error(`${label} database must be ${REQUIRED_DATABASE}`);
}

function localClient(url) {
  const bounded = new URL(withPrismaPoolParams(url));
  bounded.searchParams.set("connection_limit", "1");
  return new PrismaClient({ datasources: { db: { url: bounded.toString() } } });
}

async function counts(prisma) {
  const rows = [];
  for (const [table, delegate] of TABLES) {
    rows.push({ table, count: await prisma[delegate].count() });
  }
  return rows;
}

async function assertEmpty(prisma) {
  const rows = await counts(prisma);
  const dirty = rows.filter((row) => row.count !== 0);
  if (dirty.length) {
    throw new Error(`REFERRAL_TABLES_NOT_EMPTY ${dirty.map((row) => `${row.table}=${row.count}`).join(" ")}`);
  }
}

async function sessionPid(prisma) {
  const rows = await prisma.$queryRaw`SELECT pg_backend_pid() AS pid`;
  return Number(rows[0].pid);
}

async function claimOne(prisma, { referrerId, versionId, codeId, referredId, cap }) {
  try {
    return await prisma.$transaction(async (tx) => {
      const pid = await sessionPid(tx);
      console.log(`attribution session pid ${pid}`);
      await tx.$queryRaw`
        SELECT id FROM "IncentiveReferralCode"
        WHERE "userId" = ${referrerId} AND "campaignVersionId" = ${versionId}
        ORDER BY id
        FOR UPDATE
      `;
      const used = await tx.incentiveReferral.count({
        where: { referrerUserId: referrerId, campaignVersionId: versionId, acquisitionKind: "BUYER_ACQUISITION" },
      });
      if (used >= cap) {
        const error = new Error("Referral limit has been reached");
        error.code = "REFERRAL_LIMIT";
        throw error;
      }
      return tx.incentiveReferral.create({
        data: {
          codeId,
          referrerUserId: referrerId,
          referredUserId: referredId,
          acquisitionKind: "BUYER_ACQUISITION",
          campaignVersionId: versionId,
          status: "ATTRIBUTED",
        },
      });
    });
  } catch (error) {
    if (error.code === "REFERRAL_LIMIT") return { limited: true };
    throw error;
  }
}

async function qualifyOne(prisma, { id, referrerId, versionId, cap }) {
  try {
    return await prisma.$transaction(async (tx) => {
      const pid = await sessionPid(tx);
      console.log(`qualification session pid ${pid}`);
      await tx.$queryRaw`
        SELECT id FROM "IncentiveReferralCode"
        WHERE "userId" = ${referrerId} AND "campaignVersionId" = ${versionId}
        ORDER BY id
        FOR UPDATE
      `;
      const used = await tx.incentiveReferral.count({
        where: {
          referrerUserId: referrerId,
          campaignVersionId: versionId,
          acquisitionKind: "BUYER_ACQUISITION",
          status: { in: ["QUALIFIED", "PENDING_REVIEW"] },
        },
      });
      if (used >= cap) {
        const error = new Error("Referral limit has been reached");
        error.code = "REFERRAL_LIMIT";
        throw error;
      }
      return tx.incentiveReferral.update({ where: { id }, data: { status: "QUALIFIED" } });
    });
  } catch (error) {
    if (error.code === "REFERRAL_LIMIT") return { limited: true };
    throw error;
  }
}

async function cleanup(prisma, referrerId) {
  const events = await prisma.incentiveEvent.findMany({
    where: { eventId: { startsWith: PREFIX } },
    select: { id: true },
  });
  const eventIds = events.map((row) => row.id);
  if (eventIds.length) {
    await prisma.incentiveAuditLog.deleteMany({ where: { incentiveEventId: { in: eventIds } } });
    await prisma.incentiveEvent.deleteMany({ where: { id: { in: eventIds } } });
  }
  await prisma.incentiveAuditLog.deleteMany({ where: { actorId: PREFIX } });
  await prisma.incentiveReferral.deleteMany({
    where: {
      OR: [
        { referrerUserId: { startsWith: PREFIX } },
        { referredUserId: { startsWith: PREFIX } },
      ],
    },
  });
  await prisma.incentiveReferralCode.deleteMany({
    where: { OR: [{ userId: referrerId }, { code: { startsWith: PREFIX } }] },
  });
  await prisma.incentiveCampaign.deleteMany({ where: { name: PREFIX } });
}

async function main() {
  assertSafeUrl("DATABASE_URL", process.env.DATABASE_URL);
  assertSafeUrl("DIRECT_URL", process.env.DIRECT_URL);
  const first = localClient(process.env.DATABASE_URL);
  const second = localClient(process.env.DIRECT_URL);
  const referrerId = `${PREFIX}-referrer`;
  const versionId = `${PREFIX}-version`;
  let failure = null;
  try {
    const identity = await first.$queryRaw`
      SELECT current_database() AS database,
             inet_server_addr()::text AS host,
             inet_server_port() AS port
    `;
    const target = identity[0];
    assert(target.database === REQUIRED_DATABASE, "connected database");
    assert(String(target.host).startsWith(REQUIRED_HOST), "connected host");
    assert(Number(target.port) === Number(REQUIRED_PORT), "connected port");
    const firstPid = await sessionPid(first);
    const secondPid = await sessionPid(second);
    assert(firstPid !== secondPid, "the two clients use independent PostgreSQL sessions");
    console.log(`connection ${REQUIRED_HOST}:${REQUIRED_PORT}/${REQUIRED_DATABASE}`);
    console.log(`session pids ${firstPid} ${secondPid}`);
    await assertEmpty(first);

    const campaign = await first.incentiveCampaign.create({
      data: { name: PREFIX, category: "BUYER_ACQUISITION", status: "ACTIVE" },
    });
    const buyerCode = await first.incentiveReferralCode.create({
      data: {
        userId: referrerId,
        audience: "BUYER",
        code: `${PREFIX}BUYERCODE01`,
        campaignId: campaign.id,
        scopeKey: campaign.id,
        campaignVersionId: versionId,
      },
    });
    const anyCode = await first.incentiveReferralCode.create({
      data: {
        userId: referrerId,
        audience: "ANY",
        code: `${PREFIX}ANYCODE0001`,
        campaignId: campaign.id,
        scopeKey: `${campaign.id}:any`,
        campaignVersionId: versionId,
      },
    });

    const claims = await Promise.all([
      claimOne(first, { referrerId, versionId, codeId: buyerCode.id, referredId: `${PREFIX}-a`, cap: 1 }),
      claimOne(second, { referrerId, versionId, codeId: anyCode.id, referredId: `${PREFIX}-b`, cap: 1 }),
    ]);
    const stored = await first.incentiveReferral.count({
      where: { referrerUserId: referrerId, acquisitionKind: "BUYER_ACQUISITION" },
    });
    assert(stored === 1, "attribution cap allows one row across two codes");
    assert(claims.filter((row) => row && row.limited).length === 1, "one concurrent attribution is rejected");
    console.log("attribution cap race ok");

    const winner = await first.incentiveReferral.findFirst({ where: { referrerUserId: referrerId } });
    const extra = await first.incentiveReferral.create({
      data: {
        codeId: anyCode.id,
        referrerUserId: referrerId,
        referredUserId: `${PREFIX}-c`,
        acquisitionKind: "BUYER_ACQUISITION",
        campaignVersionId: versionId,
        status: "ATTRIBUTED",
      },
    });
    const qualified = await Promise.all([
      qualifyOne(first, { id: winner.id, referrerId, versionId, cap: 1 }),
      qualifyOne(second, { id: extra.id, referrerId, versionId, cap: 1 }),
    ]);
    const qualifiedCount = await first.incentiveReferral.count({
      where: { referrerUserId: referrerId, status: "QUALIFIED" },
    });
    assert(qualifiedCount === 1, "qualified cap allows one row");
    assert(qualified.filter((row) => row && row.limited).length === 1, "one concurrent qualification is rejected");
    console.log("qualified cap race ok");

    const seenWinner = await second.incentiveReferral.findUnique({ where: { id: winner.id } });
    const seenExtra = await second.incentiveReferral.findUnique({ where: { id: extra.id } });
    assert(seenWinner && seenWinner.status === "QUALIFIED" && seenWinner.campaignVersionId === versionId, "qualified referral persisted");
    assert(seenExtra && seenExtra.status === "ATTRIBUTED", "capped referral stayed attributed");
    console.log("referral persistence ok");

    let selfRejected = false;
    try {
      await second.incentiveReferral.create({
        data: {
          codeId: buyerCode.id,
          referrerUserId: `${PREFIX}-same`,
          referredUserId: `${PREFIX}-same`,
          acquisitionKind: "SELLER_ACQUISITION",
          campaignVersionId: versionId,
          status: "ATTRIBUTED",
        },
      });
    } catch (error) {
      selfRejected = String(error.message || "").includes("IncentiveReferral_users_distinct");
    }
    const selfRows = await first.incentiveReferral.count({
      where: { referrerUserId: `${PREFIX}-same` },
    });
    assert(selfRejected && selfRows === 0, "self-referral database constraint");
    console.log("self-referral constraint ok");

    await first.incentiveReferral.create({
      data: {
        codeId: buyerCode.id,
        referrerUserId: referrerId,
        referredUserId: `${PREFIX}-idem`,
        acquisitionKind: "BUYER_ACQUISITION",
        campaignVersionId: versionId,
        status: "ATTRIBUTED",
      },
    });
    let duplicate = false;
    try {
      await second.incentiveReferral.create({
        data: {
          codeId: anyCode.id,
          referrerUserId: referrerId,
          referredUserId: `${PREFIX}-idem`,
          acquisitionKind: "BUYER_ACQUISITION",
          campaignVersionId: versionId,
          status: "ATTRIBUTED",
        },
      });
    } catch (error) {
      duplicate = error.code === "P2002";
    }
    const idemCount = await first.incentiveReferral.count({
      where: { referredUserId: `${PREFIX}-idem`, acquisitionKind: "BUYER_ACQUISITION" },
    });
    assert(duplicate && idemCount === 1, "idempotent attribution");
    console.log("idempotent attribution ok");

    const repository = createPrismaEventRepository(first);
    const rollbackToken = crypto.randomUUID();
    const rollbackEvent = await first.incentiveEvent.create({
      data: {
        eventId: `${PREFIX}-rollback`,
        type: "USER_BECAME_SELLER",
        entityType: "user",
        entityId: `${PREFIX}-seller`,
        occurredAt: new Date(),
        payload: {},
        status: "PROCESSING",
        attempts: 1,
        claimToken: rollbackToken,
      },
    });
    let rolledBack = false;
    try {
      await repository.finish(rollbackEvent.id, rollbackToken, {
        status: "PROCESSED",
        processedAt: new Date(),
        projectReferral: async () => {
          throw new Error("projection failed");
        },
        audit: {
          actorId: PREFIX,
          action: "EVENT_PROCESSED",
          incentiveEventId: rollbackEvent.id,
          attemptNumber: 1,
        },
      });
    } catch (error) {
      rolledBack = error.message === "projection failed";
    }
    const rollbackSeen = await second.incentiveEvent.findUnique({ where: { id: rollbackEvent.id } });
    const rollbackAudits = await second.incentiveAuditLog.count({ where: { incentiveEventId: rollbackEvent.id } });
    assert(rolledBack, "event finish throws when projection throws");
    assert(rollbackSeen && rollbackSeen.status === "PROCESSING" && rollbackSeen.claimToken === rollbackToken, "event finish rolls back the outcome");
    assert(rollbackAudits === 0, "event finish rolls back the audit");
    console.log("event finish rollback ok");

    const auditToken = crypto.randomUUID();
    const auditEvent = await first.incentiveEvent.create({
      data: {
        eventId: `${PREFIX}-audit`,
        type: "USER_BECAME_SELLER",
        entityType: "user",
        entityId: `${PREFIX}-seller-2`,
        occurredAt: new Date(),
        payload: {},
        status: "PROCESSING",
        attempts: 1,
        claimToken: auditToken,
      },
    });
    const finished = await repository.finish(auditEvent.id, auditToken, {
      status: "PROCESSED",
      processedAt: new Date(),
      projectReferral: async (tx) => {
        await tx.incentiveReferral.update({
          where: { id: winner.id },
          data: { sellerEnabledAt: new Date("2026-11-17T00:00:00.000Z") },
        });
      },
      audit: {
        actorId: PREFIX,
        action: "EVENT_PROCESSED",
        incentiveEventId: auditEvent.id,
        attemptNumber: 1,
      },
    });
    const auditSeen = await second.incentiveEvent.findUnique({ where: { id: auditEvent.id } });
    const auditRow = await second.incentiveAuditLog.findFirst({ where: { incentiveEventId: auditEvent.id, actorId: PREFIX } });
    const projected = await second.incentiveReferral.findUnique({ where: { id: winner.id } });
    assert(finished.applied === true, "event finish applied");
    assert(auditSeen && auditSeen.status === "PROCESSED" && auditSeen.claimToken === null, "processed event persisted");
    assert(auditRow && auditRow.action === "EVENT_PROCESSED", "audit persisted");
    assert(projected && projected.sellerEnabledAt, "referral update persisted with the event");
    console.log("audit persistence ok");
  } catch (error) {
    failure = error;
  } finally {
    try {
      await cleanup(first, referrerId);
      const left = await counts(first);
      const dirty = left.filter((row) => row.count !== 0);
      if (dirty.length) {
        console.error(`CLEANUP_FAILED ${dirty.map((row) => `${row.table}=${row.count}`).join(" ")}`);
        failure = failure || new Error("CLEANUP_FAILED");
      } else {
        console.log("cleanup ok");
      }
    } catch (error) {
      console.error("CLEANUP_FAILED");
      failure = failure || error;
    }
    await first.$disconnect();
    await second.$disconnect();
  }
  if (failure) throw failure;
  console.log("incentive referral postgresql integration ok");
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
