/**
 * Local PostgreSQL integration for incentive event processing.
 * Not part of npm test, test:unit, or test:regression.
 *
 * Refuses every database except 127.0.0.1:5432/societybites_incentive_foundation.
 * Does not read .env. Does not issue rewards, referrals, or ledger rows.
 * The foundation database has no Order table, so order qualification is not executed here.
 * An ORDER_QUALIFIED event fails in loadOrder and exercises the real retry path.
 */
const crypto = require("crypto");
const { PrismaClient } = require("@prisma/client");
const { withPrismaPoolParams } = require("../lib/prismaPool");
const { LEASE_MS, BASE_DELAY_MS, MAX_DELAY_MS } = require("../modules/incentive-engine/events/lifecycle");
const { createPrismaEventRepository } = require("../modules/incentive-engine/events/repository");
const { ingestEvent, processDue, recoverExpired, replayEvent } = require("../modules/incentive-engine/events/process");

const REQUIRED_HOST = "127.0.0.1";
const REQUIRED_PORT = "5432";
const REQUIRED_DATABASE = "societybites_incentive_foundation";
const PREFIX = `p2c${crypto.randomBytes(6).toString("hex")}`;
const EMPTY_MODELS = [
  "incentiveSetting",
  "incentiveCampaign",
  "incentiveCampaignVersion",
  "incentiveAudience",
  "incentiveTrigger",
  "incentiveRule",
  "incentiveRewardDefinition",
  "incentiveBudget",
  "incentiveEvent",
  "incentiveReferralCode",
  "incentiveReferral",
  "incentiveReward",
  "incentiveLedgerEntry",
  "incentiveRedemption",
  "incentiveRiskEvaluation",
  "incentiveApproval",
  "incentiveAuditLog",
];
const PROTECTED_MODELS = [
  "incentiveReward",
  "incentiveReferral",
  "incentiveReferralCode",
  "incentiveLedgerEntry",
  "incentiveRedemption",
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
  let parsed;
  try {
    parsed = new URL(value);
  } catch (error) {
    throw new Error(`${label} is not a valid database URL`);
  }
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

async function expectError(work, code) {
  try {
    await work();
  } catch (error) {
    assert(!code || error.code === code, `expected ${code} but got ${error.code || error.message}`);
    return error;
  }
  throw new Error(`expected ${code || "an error"}`);
}

async function counts(db) {
  const totals = {};
  for (const model of EMPTY_MODELS) totals[model] = await db[model].count();
  return totals;
}

function assertEmpty(totals, label) {
  for (const model of EMPTY_MODELS) {
    assert(totals[model] === 0, `${label}: ${model} has ${totals[model]} rows`);
  }
}

async function backendPid(db) {
  const rows = await db.$queryRaw`SELECT pg_backend_pid() AS pid, current_database() AS database_name, inet_server_addr()::text AS server_addr`;
  return rows[0];
}

function ownEvents() {
  return {
    OR: [
      { entityId: { startsWith: PREFIX } },
      { eventId: { contains: PREFIX } },
      { userId: { startsWith: PREFIX } },
    ],
  };
}

async function main() {
  assertSafeUrl("DATABASE_URL", process.env.DATABASE_URL);
  assertSafeUrl("DIRECT_URL", process.env.DIRECT_URL);
  const sessionA = localClient(process.env.DATABASE_URL);
  const sessionB = localClient(process.env.DIRECT_URL);
  const repoA = createPrismaEventRepository(sessionA);
  const repoB = createPrismaEventRepository(sessionB);
  let ownsMaster = false;
  let failed = null;

  async function setMaster(value) {
    if (value == null) {
      await sessionA.incentiveSetting.deleteMany({ where: { key: "master_enabled" } });
      return;
    }
    await sessionA.incentiveSetting.upsert({
      where: { key: "master_enabled" },
      create: { key: "master_enabled", value },
      update: { value },
    });
    ownsMaster = true;
  }

  async function ingest(type, suffix, extra) {
    return ingestEvent(repoA, {
      type,
      entityId: `${PREFIX}-${suffix}`,
      userId: PREFIX,
      occurredAt: new Date().toISOString(),
      ...extra,
    });
  }

  async function cleanup() {
    const events = await sessionA.incentiveEvent.findMany({ where: ownEvents(), select: { id: true } });
    const ids = events.map((event) => event.id);
    if (ids.length > 0) {
      await sessionA.incentiveAuditLog.deleteMany({ where: { incentiveEventId: { in: ids } } });
      const removedEvents = await sessionA.incentiveEvent.deleteMany({ where: { id: { in: ids } } });
      if (removedEvents.count !== ids.length) {
        throw new Error(`cleanup removed ${removedEvents.count} of ${ids.length} events`);
      }
    }
    if (ownsMaster) {
      await sessionA.incentiveSetting.deleteMany({ where: { key: "master_enabled" } });
    }
    const remaining = await sessionA.incentiveEvent.count({ where: ownEvents() });
    const remainingAudits = await sessionA.incentiveAuditLog.count({
      where: { OR: [{ actorId: { startsWith: PREFIX } }, { incentiveEventId: { in: ids } }] },
    });
    if (remaining !== 0 || remainingAudits !== 0) {
      throw new Error(`cleanup left events=${remaining} audits=${remainingAudits}`);
    }
    const after = await counts(sessionA);
    assertEmpty(after, "after cleanup");
    for (const model of PROTECTED_MODELS) {
      assert(after[model] === 0, `${model} was written during the test`);
    }
  }

  try {
    const [identityA, identityB] = await Promise.all([backendPid(sessionA), backendPid(sessionB)]);
    assert(String(identityA.pid) !== String(identityB.pid), "sessions did not open independent connections");
    assert(identityA.database_name === REQUIRED_DATABASE && identityB.database_name === REQUIRED_DATABASE, "connected database is not the foundation database");
    assert(String(identityA.server_addr).startsWith(REQUIRED_HOST) && String(identityB.server_addr).startsWith(REQUIRED_HOST), "server address is not 127.0.0.1");

    const indexes = await sessionA.$queryRaw`
      SELECT indexname, indexdef
      FROM pg_indexes
      WHERE schemaname = 'public'
        AND indexname IN ('IncentiveEvent_one_terminal_order_event', 'IncentiveAuditLog_processing_outcome_key')
      ORDER BY indexname
    `;
    assert(indexes.length === 2, "both partial unique indexes must exist");
    const byName = Object.fromEntries(indexes.map((row) => [row.indexname, row.indexdef]));
    const orderIndex = byName.IncentiveEvent_one_terminal_order_event;
    const auditIndex = byName.IncentiveAuditLog_processing_outcome_key;
    assert(orderIndex.includes('UNIQUE INDEX "IncentiveEvent_one_terminal_order_event"'), "order index name mismatch");
    assert(orderIndex.includes('("entityId")'), "order index must be on entityId");
    assert(orderIndex.includes("\"entityType\" = 'order'::text"), "order index must restrict entityType");
    assert(orderIndex.includes("'ORDER_QUALIFIED'::text"), "order index must include ORDER_QUALIFIED");
    assert(orderIndex.includes("'ORDER_CANCELLED'::text"), "order index must include ORDER_CANCELLED");
    assert(orderIndex.includes("'ORDER_REJECTED'::text"), "order index must include ORDER_REJECTED");
    assert(auditIndex.includes('("incentiveEventId", action, "attemptNumber")'), "audit index columns mismatch");
    assert(auditIndex.includes('"incentiveEventId" IS NOT NULL'), "audit index must ignore rows without an event");
    for (const action of ["EVENT_PROCESSED", "EVENT_SKIPPED", "EVENT_FAILED", "EVENT_DEAD", "EVENT_RECOVERED"]) {
      assert(auditIndex.includes(`'${action}'::text`), `audit index must include ${action}`);
    }
    assert(!auditIndex.includes("EVENT_REPLAY"), "replay audits are outside the unique index");

    assertEmpty(await counts(sessionA), "before tests");

    await expectError(
      () => ingest("NOT_AN_EVENT", "invalid-type"),
      "EVENT_TYPE_INVALID"
    );
    await expectError(
      () => ingest("USER_REGISTERED", "bad-payload", { payload: { sql: "select 1" } }),
      "EVENT_INVALID"
    );
    assert((await sessionA.incentiveEvent.count({ where: ownEvents() })) === 0, "rejected input inserted a row");

    const created = await ingest("USER_REGISTERED", "once");
    const duplicate = await ingest("USER_REGISTERED", "once");
    assert(created.created === true && duplicate.created === false, "duplicate ingest must return the original event");
    assert(created.event.id === duplicate.event.id, "duplicate ingest returned a different row");
    assert((await sessionA.incentiveEvent.count({ where: { entityId: `${PREFIX}-once` } })) === 1, "duplicate ingest inserted a second row");
    assert((await sessionA.incentiveAuditLog.count({ where: { incentiveEventId: created.event.id } })) === 0, "ingest wrote an audit");

    await ingest("ORDER_QUALIFIED", "terminal");
    await expectError(() => ingest("ORDER_CANCELLED", "terminal"), "ORDER_TERMINAL_CONFLICT");
    assert((await sessionA.incentiveEvent.count({ where: { entityId: `${PREFIX}-terminal` } })) === 1, "terminal conflict left more than one row");

    const claimEvent = await ingest("USER_REGISTERED", "claim");
    const missing = await repoB.claim(claimEvent.event.id, { now: new Date(), workerId: `${PREFIX}-missing` });
    assert(missing.blocked === true, "missing master flag must block the claim");
    await setMaster("false");
    const off = await repoB.claim(claimEvent.event.id, { now: new Date(), workerId: `${PREFIX}-off` });
    assert(off.blocked === true, "false master flag must block the claim");
    await setMaster(" false ");
    const padded = await repoB.claim(claimEvent.event.id, { now: new Date(), workerId: `${PREFIX}-padded` });
    assert(padded.blocked === true, "space-padded false must block the claim");
    let stored = await sessionB.incentiveEvent.findUnique({ where: { id: claimEvent.event.id } });
    assert(stored.status === "PENDING" && stored.attempts === 0 && stored.claimToken == null, "blocked claim changed the event");

    await setMaster("true");
    const claimed = await repoA.claim(claimEvent.event.id, { now: new Date(), workerId: `${PREFIX}-owner` });
    assert(claimed.claimed === true, "true master flag must allow the claim");
    stored = await sessionB.incentiveEvent.findUnique({ where: { id: claimEvent.event.id } });
    assert(stored.status === "PROCESSING" && stored.attempts === 1 && stored.claimToken === claimed.token, "claim did not store its token");

    const raceOff = await ingest("USER_REGISTERED", "race-off");
    await sessionA.incentiveSetting.update({ where: { key: "master_enabled" }, data: { value: "false" } });
    const blockedAfterCommit = await repoB.claim(raceOff.event.id, { now: new Date(), workerId: `${PREFIX}-after-off` });
    assert(blockedAfterCommit.blocked === true, "a committed master OFF must block the other session");
    stored = await sessionB.incentiveEvent.findUnique({ where: { id: raceOff.event.id } });
    assert(stored.status === "PENDING" && stored.attempts === 0, "blocked session changed the event");

    await sessionA.incentiveSetting.update({ where: { key: "master_enabled" }, data: { value: "true" } });
    const raceOn = await ingest("USER_REGISTERED", "race-on");
    const committedClaim = await repoB.claim(raceOn.event.id, { now: new Date(), workerId: `${PREFIX}-before-off` });
    assert(committedClaim.claimed === true, "claim must commit while master is on");
    await sessionA.incentiveSetting.update({ where: { key: "master_enabled" }, data: { value: "false" } });
    const finishedAfterOff = await repoB.finish(raceOn.event.id, committedClaim.token, {
      status: "PROCESSED",
      processedAt: new Date(),
      audit: {
        actorId: `${PREFIX}-before-off`,
        action: "EVENT_PROCESSED",
        incentiveEventId: raceOn.event.id,
        attemptNumber: committedClaim.event.attempts,
      },
    });
    assert(finishedAfterOff.applied === true, "a committed claim may finish after master turns off");
    stored = await sessionA.incentiveEvent.findUnique({ where: { id: raceOn.event.id } });
    assert(stored.status === "PROCESSED" && stored.claimToken == null, "finished claim did not clear its token");

    await setMaster("true");
    const contested = await ingest("USER_REGISTERED", "contested");
    const now = new Date();
    const [first, second] = await Promise.all([
      repoA.claim(contested.event.id, { now, workerId: `${PREFIX}-a` }),
      repoB.claim(contested.event.id, { now, workerId: `${PREFIX}-b` }),
    ]);
    const winners = [first, second].filter((result) => result.claimed === true);
    assert(winners.length === 1, "two workers claimed the same event");
    stored = await sessionA.incentiveEvent.findUnique({ where: { id: contested.event.id } });
    assert(stored.attempts === 1 && stored.claimToken === winners[0].token, "the losing claim changed the token or attempt count");
    const loser = first.claimed ? second : first;
    const stale = await (first.claimed ? repoB : repoA).finish(contested.event.id, loser.token || "stale-token", {
      status: "SKIPPED",
      audit: {
        actorId: `${PREFIX}-stale`,
        action: "EVENT_SKIPPED",
        incentiveEventId: contested.event.id,
        attemptNumber: 1,
      },
    });
    assert(stale.applied === false, "stale token updated the event");
    stored = await sessionB.incentiveEvent.findUnique({ where: { id: contested.event.id } });
    assert(stored.status === "PROCESSING" && stored.claimToken === winners[0].token, "stale token changed the stored claim");
    assert((await sessionA.incentiveAuditLog.count({ where: { incentiveEventId: contested.event.id } })) === 0, "stale token inserted an audit");

    const lease = await ingest("USER_REGISTERED", "lease");
    const leaseClaim = await repoA.claim(lease.event.id, { now: new Date(), workerId: `${PREFIX}-lease` });
    await sessionA.incentiveEvent.update({
      where: { id: lease.event.id },
      data: { claimedAt: new Date(Date.now() - LEASE_MS - 5000) },
    });
    const recovered = await recoverExpired(repoB, { now: new Date(), actorId: `${PREFIX}-admin` });
    const leaseResult = recovered.recovered.find((row) => row.id === lease.event.id);
    assert(leaseResult && leaseResult.applied === true && leaseResult.status === "FAILED", "expired lease was not recovered");
    stored = await sessionA.incentiveEvent.findUnique({ where: { id: lease.event.id } });
    assert(stored.attempts === 1 && stored.status === "FAILED" && stored.claimToken == null, "recovery changed the attempt count");
    const staleLease = await repoA.finish(lease.event.id, leaseClaim.token, {
      status: "PROCESSED",
      audit: {
        actorId: `${PREFIX}-stale-lease`,
        action: "EVENT_PROCESSED",
        incentiveEventId: lease.event.id,
        attemptNumber: 1,
      },
    });
    assert(staleLease.applied === false, "expired worker overwrote recovery");
    assert((await sessionB.incentiveAuditLog.count({ where: { incentiveEventId: lease.event.id, action: "EVENT_PROCESSED" } })) === 0, "expired worker inserted an audit");
    assert((await sessionB.incentiveAuditLog.count({ where: { incentiveEventId: lease.event.id, action: "EVENT_RECOVERED", attemptNumber: 1 } })) === 1, "recovery audit is missing");

    await setMaster("true");
    const retry = await ingest("ORDER_QUALIFIED", "retry");
    await sessionA.incentiveEvent.updateMany({
      where: {
        AND: [ownEvents(), { id: { not: retry.event.id } }, { status: { in: ["PENDING", "FAILED"] } }],
      },
      data: { nextAttemptAt: new Date("2099-01-01T00:00:00.000Z") },
    });
    let cursor = new Date();
    for (let attempt = 1; attempt <= 8; attempt += 1) {
      const batch = await processDue(repoA, { now: cursor, workerId: `${PREFIX}-retry` });
      const outcome = batch.processed.find((row) => row.id === retry.event.id);
      stored = await sessionB.incentiveEvent.findUnique({ where: { id: retry.event.id } });
      const expected = attempt === 8 ? "DEAD" : "FAILED";
      assert(outcome && outcome.status === expected, `attempt ${attempt} returned ${outcome && outcome.status}`);
      assert(stored.attempts === attempt && stored.status === expected, `attempt ${attempt} was not stored`);
      if (attempt < 8) {
        const expectedDelay = Math.min(BASE_DELAY_MS * 2 ** (attempt - 1), MAX_DELAY_MS);
        const actualDelay = new Date(stored.nextAttemptAt).getTime() - cursor.getTime();
        assert(Math.abs(actualDelay - expectedDelay) < 2000, `attempt ${attempt} delay was ${actualDelay}`);
        await sessionA.incentiveEvent.update({
          where: { id: retry.event.id },
          data: { nextAttemptAt: new Date(cursor.getTime() - 1000) },
        });
      } else {
        assert(stored.nextAttemptAt == null, "dead event kept a retry time");
      }
      cursor = new Date(cursor.getTime() + 1000);
    }

    const replaySource = await ingest("USER_REGISTERED", "replay");
    const firstAttempt = await repoA.claim(replaySource.event.id, { now: new Date(), workerId: `${PREFIX}-replay` });
    await repoA.finish(replaySource.event.id, firstAttempt.token, {
      status: "FAILED",
      nextAttemptAt: new Date(),
      audit: {
        actorId: `${PREFIX}-replay`,
        action: "EVENT_FAILED",
        incentiveEventId: replaySource.event.id,
        attemptNumber: firstAttempt.event.attempts,
      },
    });
    const replayed = await replayEvent(repoB, { id: replaySource.event.id, actorId: `${PREFIX}-admin` });
    assert(replayed.event.status === "PENDING" && replayed.event.attempts === 1, "replay did not preserve attempts");
    const secondAttempt = await repoA.claim(replaySource.event.id, { now: new Date(), workerId: `${PREFIX}-replay-2` });
    assert(secondAttempt.claimed === true && secondAttempt.event.attempts === 2, "the claim after replay did not increment");
    await repoA.finish(replaySource.event.id, secondAttempt.token, {
      status: "FAILED",
      nextAttemptAt: new Date(Date.now() + 60000),
      audit: {
        actorId: `${PREFIX}-replay-2`,
        action: "EVENT_FAILED",
        incentiveEventId: replaySource.event.id,
        attemptNumber: secondAttempt.event.attempts,
      },
    });
    const failureAudits = await sessionB.incentiveAuditLog.findMany({
      where: { incentiveEventId: replaySource.event.id, action: "EVENT_FAILED" },
      orderBy: { attemptNumber: "asc" },
    });
    assert(failureAudits.map((row) => row.attemptNumber).join(",") === "1,2", "replayed failure did not get a distinct audit");

    const conflict = await ingest("USER_REGISTERED", "audit-conflict");
    const conflictClaim = await repoA.claim(conflict.event.id, { now: new Date(), workerId: `${PREFIX}-conflict` });
    await sessionB.incentiveAuditLog.create({
      data: {
        actorId: `${PREFIX}-plant`,
        action: "EVENT_FAILED",
        incentiveEventId: conflict.event.id,
        attemptNumber: conflictClaim.event.attempts,
      },
    });
    const conflictError = await expectError(
      () => repoA.finish(conflict.event.id, conflictClaim.token, {
        status: "FAILED",
        lastError: "duplicate audit",
        audit: {
          actorId: `${PREFIX}-conflict`,
          action: "EVENT_FAILED",
          incentiveEventId: conflict.event.id,
          attemptNumber: conflictClaim.event.attempts,
        },
      }),
      "P2002"
    );
    assert(conflictError.code === "P2002", "duplicate audit did not raise the unique conflict");
    stored = await sessionB.incentiveEvent.findUnique({ where: { id: conflict.event.id } });
    assert(stored.status === "PROCESSING" && stored.claimToken === conflictClaim.token, "audit conflict committed the event update");
    assert(
      (await sessionA.incentiveAuditLog.count({
        where: { incentiveEventId: conflict.event.id, action: "EVENT_FAILED", attemptNumber: conflictClaim.event.attempts },
      })) === 1,
      "audit conflict left a second outcome row"
    );

    const protectedCounts = await counts(sessionA);
    for (const model of PROTECTED_MODELS) {
      assert(protectedCounts[model] === 0, `${model} was created by event processing`);
    }
    console.log("incentive events postgresql integration ok");
  } catch (error) {
    failed = error;
  } finally {
    let cleanupError = null;
    try {
      await cleanup();
    } catch (error) {
      cleanupError = error;
    }
    await sessionA.$disconnect().catch(() => {});
    await sessionB.$disconnect().catch(() => {});
    if (cleanupError) {
      if (failed) console.error(failed.message || failed);
      console.error("CLEANUP_FAILED", cleanupError.message);
      throw cleanupError;
    }
  }
  if (failed) throw failed;
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
