const { AsyncLocalStorage } = require("async_hooks");
const { httpError } = require("../lib/httpError");

const rewardLockContext = new AsyncLocalStorage();

function cents(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return null;
  return Math.round(amount * 100);
}

function money(centsValue) {
  return (centsValue / 100).toFixed(2);
}

function lockState(holder) {
  if (!holder.lockState) holder.lockState = { queues: new Map(), held: new Set() };
  return holder.lockState;
}

async function serialize(holder, key, work) {
  const state = lockState(holder);
  const frame = rewardLockContext.getStore();
  if (frame && frame.holder === holder && frame.key === key) return work();
  if (!state.queues.has(key)) state.queues.set(key, Promise.resolve());
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const previous = state.queues.get(key);
  state.queues.set(key, previous.then(() => gate));
  await previous;
  try {
    return await rewardLockContext.run({ holder, key }, work);
  } finally {
    release();
  }
}

/**
 * Holds the reward row until work finishes. PostgreSQL keeps FOR UPDATE until
 * the transaction ends, so the following balance statement sees rows committed
 * by the transaction that previously held this reward. A second lock of the
 * same reward in that transaction does not wait again.
 */
async function withRewardLock(tx, rewardId, work) {
  if (typeof tx.$queryRaw === "function") {
    const rows = await tx.$queryRaw`
      SELECT "id"
      FROM "IncentiveReward"
      WHERE "id" = ${rewardId}
      FOR UPDATE
    `;
    if (!rows.length) return null;
    return work();
  }
  if (!tx.incentiveReward) return null;
  return serialize(tx.incentiveReward, rewardId, work);
}

async function balanceOf(tx, rewardId) {
  if (!tx || !tx.incentiveLedgerEntry || typeof tx.incentiveLedgerEntry.findMany !== "function") return 0;
  const rows = await tx.incentiveLedgerEntry.findMany({ where: { rewardId } });
  return rows.reduce((sum, row) => sum + Number(row.amount), 0);
}

async function insertEntry(tx, { rewardId, entryType, amount, actorId, reason, idempotencyKey, value }) {
  const existing = await tx.incentiveLedgerEntry.findUnique({ where: { idempotencyKey } });
  if (existing) {
    if (cents(existing.amount) !== value) {
      throw httpError(409, "This idempotency key was already used for a different amount", "IDEMPOTENCY_CONFLICT");
    }
    return { created: false, entry: existing };
  }
  const current = cents(await balanceOf(tx, rewardId));
  if (current + value < 0) {
    throw httpError(409, "Credit balance is not sufficient", "INSUFFICIENT_CREDIT");
  }
  try {
    const entry = await tx.incentiveLedgerEntry.create({
      data: {
        rewardId,
        entryType,
        amount: money(value),
        currency: "INR",
        actorId: actorId || null,
        reason: reason || null,
        idempotencyKey,
      },
    });
    return { created: true, entry };
  } catch (error) {
    if (error && error.code === "P2002") {
      const saved = await tx.incentiveLedgerEntry.findUnique({ where: { idempotencyKey } });
      if (saved) {
        if (cents(saved.amount) !== value) {
          throw httpError(409, "This idempotency key was already used for a different amount", "IDEMPOTENCY_CONFLICT");
        }
        return { created: false, entry: saved };
      }
    }
    throw error;
  }
}

async function postEntry(tx, { rewardId, entryType, amount, actorId, reason, idempotencyKey }) {
  if (!rewardId || !entryType || !idempotencyKey) {
    throw httpError(400, "A ledger entry needs a source and an idempotency key", "LEDGER_SOURCE_REQUIRED");
  }
  const value = cents(amount);
  if (value == null || value === 0) throw httpError(400, "Ledger amount must be non-zero", "LEDGER_AMOUNT_INVALID");
  if (entryType !== "ISSUE" && entryType !== "REDEEM" && entryType !== "EXPIRE") {
    throw httpError(400, "Ledger entry type is not supported", "LEDGER_ENTRY_UNSUPPORTED");
  }
  if (entryType === "ISSUE" && value < 0) throw httpError(400, "A credit must be positive", "LEDGER_AMOUNT_INVALID");
  if ((entryType === "REDEEM" || entryType === "EXPIRE") && value > 0) {
    throw httpError(400, "A debit must be negative", "LEDGER_AMOUNT_INVALID");
  }
  const saved = await withRewardLock(tx, rewardId, () =>
    insertEntry(tx, { rewardId, entryType, amount, actorId, reason, idempotencyKey, value })
  );
  if (saved == null) throw httpError(404, "Reward not found", "REWARD_NOT_FOUND");
  return saved;
}

module.exports = {
  balanceOf,
  cents,
  withRewardLock,
  money,
  postEntry,
};
