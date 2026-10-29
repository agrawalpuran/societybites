const {
  INTERVAL_MS,
  MAX_TITLE,
  MAX_BODY,
  computeCooldownStatus,
  normalizeCopy,
} = require("../lib/marketingPush");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(INTERVAL_MS === 7 * 24 * 60 * 60 * 1000, "7-day interval");

const fresh = computeCooldownStatus(null, new Date("2026-10-29T12:00:00.000Z"));
assert(fresh.canSend === true, "never sent => can send");
assert(fresh.lastSentAt === null, "no last sent");
assert(fresh.remainingMs === 0, "no remaining wait");

const last = "2026-10-22T12:00:00.000Z";
const midWeek = computeCooldownStatus(
  last,
  new Date("2026-10-25T12:00:00.000Z")
);
assert(midWeek.canSend === false, "within week => blocked");
assert(midWeek.lastSentAt === last, "preserves last sent");
assert(midWeek.remainingMs > 0, "has remaining ms");
assert(
  midWeek.nextAllowedAt === "2026-10-29T12:00:00.000Z",
  "next allowed = last + 7d"
);

const afterWeek = computeCooldownStatus(
  last,
  new Date("2026-10-29T12:00:00.000Z")
);
assert(afterWeek.canSend === true, "exactly 7d later => allowed");
assert(afterWeek.remainingMs === 0, "no remaining after week");

let threw = false;
try {
  normalizeCopy("", "body");
} catch (err) {
  threw = err.status === 400;
}
assert(threw, "empty title rejected");

threw = false;
try {
  normalizeCopy("title", "");
} catch (err) {
  threw = err.status === 400;
}
assert(threw, "empty body rejected");

threw = false;
try {
  normalizeCopy("x".repeat(MAX_TITLE + 1), "ok");
} catch (err) {
  threw = err.status === 400;
}
assert(threw, "title too long rejected");

threw = false;
try {
  normalizeCopy("ok", "y".repeat(MAX_BODY + 1));
} catch (err) {
  threw = err.status === 400;
}
assert(threw, "body too long rejected");

const copy = normalizeCopy("  Hello  ", "  World  ");
assert(copy.title === "Hello" && copy.body === "World", "trims copy");

console.log("marketing-push.test.js passed");
