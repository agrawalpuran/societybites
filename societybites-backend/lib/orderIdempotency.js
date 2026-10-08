const { randomUUID } = require("crypto");

const MIN_KEY_LENGTH = 8;
const MAX_KEY_LENGTH = 128;
const WAIT_TIMEOUT_MS = 30_000;
const POLL_INTERVAL_MS = 50;

class IdempotencyInProgressError extends Error {
  constructor() {
    super("Order idempotency slot in progress");
    this.name = "IdempotencyInProgressError";
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isUniqueViolation(err) {
  return err && err.code === "P2002";
}

/**
 * @param {import('express').Request} req
 * @returns {string | null}
 */
function parseIdempotencyKey(req) {
  const raw = req.header("Idempotency-Key") || req.header("idempotency-key");
  if (raw == null || String(raw).trim() === "") return null;
  const key = String(raw).trim();
  if (key.length < MIN_KEY_LENGTH || key.length > MAX_KEY_LENGTH) {
    const err = new Error(
      `Idempotency-Key must be between ${MIN_KEY_LENGTH} and ${MAX_KEY_LENGTH} characters`
    );
    err.statusCode = 400;
    throw err;
  }
  return key;
}

async function findBuyerKeyRow(db, buyerId, idempotencyKey) {
  return db.orderIdempotency.findUnique({
    where: {
      buyerId_idempotencyKey: { buyerId, idempotencyKey },
    },
  });
}

/**
 * Claim or replay inside the order-creation transaction.
 * @returns {{ replay: true, order } | { replay: false }}
 */
async function beginIdempotentOrderSlot(tx, buyerId, idempotencyKey, orderInclude) {
  let row = await findBuyerKeyRow(tx, buyerId, idempotencyKey);

  if (!row) {
    try {
      row = await tx.orderIdempotency.create({
        data: {
          id: randomUUID(),
          buyerId,
          idempotencyKey,
          status: "PENDING",
        },
      });
      return { replay: false };
    } catch (err) {
      if (!isUniqueViolation(err)) throw err;
      row = await findBuyerKeyRow(tx, buyerId, idempotencyKey);
      if (!row) throw new IdempotencyInProgressError();
    }
  }

  if (row.orderId && row.status === "COMPLETED") {
    const order = await tx.order.findUnique({
      where: { id: row.orderId },
      include: orderInclude,
    });
    if (order) {
      return { replay: true, order };
    }
    await tx.orderIdempotency.update({
      where: { id: row.id },
      data: { status: "FAILED", orderId: null },
    });
    return { replay: false };
  }

  if (row.status === "FAILED") {
    await tx.orderIdempotency.update({
      where: { id: row.id },
      data: { status: "PENDING", orderId: null },
    });
    return { replay: false };
  }

  if (row.status === "PENDING" && !row.orderId) {
    throw new IdempotencyInProgressError();
  }

  return { replay: false };
}

/**
 * Fast path for retries after the first request already completed.
 * @returns {Promise<object | null>}
 */
async function findCompletedIdempotentOrder(prisma, buyerId, idempotencyKey, orderInclude) {
  if (!idempotencyKey) return null;
  const row = await findBuyerKeyRow(prisma, buyerId, idempotencyKey);
  if (!row?.orderId || row.status !== "COMPLETED") return null;
  const order = await prisma.order.findUnique({
    where: { id: row.orderId },
    include: orderInclude,
  });
  return order || null;
}

async function completeIdempotentOrderSlot(tx, buyerId, idempotencyKey, orderId) {
  await tx.orderIdempotency.update({
    where: {
      buyerId_idempotencyKey: { buyerId, idempotencyKey },
    },
    data: {
      orderId,
      status: "COMPLETED",
    },
  });
}

/**
 * Runs order creation with optional idempotency (same transaction as stock + order).
 *
 * @param {import('@prisma/client').PrismaClient} prisma
 * @param {{
 *   buyerId: string,
 *   idempotencyKey: string | null,
 *   orderInclude: object,
 *   createOrderInTransaction: (tx: import('@prisma/client').Prisma.TransactionClient) => Promise<object>,
 * }} input
 * @returns {Promise<{ order: object, replay: boolean }>}
 */
async function runWithOrderIdempotency(prisma, input) {
  const { buyerId, idempotencyKey, orderInclude, createOrderInTransaction } = input;

  if (!idempotencyKey) {
    const order = await prisma.$transaction(createOrderInTransaction);
    return { order, replay: false };
  }

  const deadline = Date.now() + WAIT_TIMEOUT_MS;

  while (Date.now() < deadline) {
    try {
      const result = await prisma.$transaction(async (tx) => {
        const slot = await beginIdempotentOrderSlot(
          tx,
          buyerId,
          idempotencyKey,
          orderInclude
        );
        if (slot.replay) {
          return { order: slot.order, replay: true };
        }

        const order = await createOrderInTransaction(tx);
        await completeIdempotentOrderSlot(tx, buyerId, idempotencyKey, order.id);
        return { order, replay: false };
      });
      return result;
    } catch (err) {
      if (
        (err instanceof IdempotencyInProgressError || isUniqueViolation(err)) &&
        Date.now() < deadline
      ) {
        await sleep(POLL_INTERVAL_MS);
        continue;
      }
      throw err;
    }
  }

  const timeoutErr = new Error(
    "Order submission is still processing. Please retry shortly."
  );
  timeoutErr.statusCode = 409;
  throw timeoutErr;
}

module.exports = {
  parseIdempotencyKey,
  findCompletedIdempotentOrder,
  runWithOrderIdempotency,
  IdempotencyInProgressError,
};
