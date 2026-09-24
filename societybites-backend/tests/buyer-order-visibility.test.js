const assert = require("assert");
const {
  isBuyerActiveOrder,
  BUYER_TERMINAL_ACTIVE_MS,
} = require("../lib/buyerOrderVisibility");

const now = new Date("2026-09-25T10:30:00.000Z");
const hoursAgo = (h) => new Date(now.getTime() - h * 60 * 60 * 1000).toISOString();

assert.strictEqual(
  isBuyerActiveOrder({ status: "pending" }, now),
  true,
  "pending stays active"
);
assert.strictEqual(
  isBuyerActiveOrder({ status: "accepted" }, now),
  true,
  "accepted stays active"
);
assert.strictEqual(
  isBuyerActiveOrder({ status: "ready" }, now),
  true,
  "ready stays active"
);

assert.strictEqual(
  isBuyerActiveOrder(
    { status: "completed", completedAt: hoursAgo(3) },
    now
  ),
  true,
  "completed <24h is active"
);
assert.strictEqual(
  isBuyerActiveOrder(
    { status: "completed", completedAt: hoursAgo(24) },
    now
  ),
  false,
  "completed =24h is past"
);
assert.strictEqual(
  isBuyerActiveOrder(
    { status: "completed", timeline: { completedAt: hoursAgo(30) } },
    now
  ),
  false,
  "completed >24h is past"
);

assert.strictEqual(
  isBuyerActiveOrder(
    { status: "rejected", rejectedAt: hoursAgo(5) },
    now
  ),
  true,
  "rejected <24h is active"
);
assert.strictEqual(
  isBuyerActiveOrder(
    { status: "rejected", rejectedAt: hoursAgo(25) },
    now
  ),
  false,
  "rejected >24h is past"
);

assert.strictEqual(
  isBuyerActiveOrder(
    { status: "cancelled", cancelledAt: hoursAgo(1) },
    now
  ),
  true,
  "cancelled <24h is active"
);
assert.strictEqual(
  isBuyerActiveOrder(
    { status: "cancelled", cancelledAt: hoursAgo(48) },
    now
  ),
  false,
  "cancelled >24h is past"
);

assert.strictEqual(
  isBuyerActiveOrder({ status: "completed" }, now),
  false,
  "terminal without timestamp is past"
);

assert.ok(BUYER_TERMINAL_ACTIVE_MS === 24 * 60 * 60 * 1000);

console.log("buyer-order-visibility.test.js passed");
