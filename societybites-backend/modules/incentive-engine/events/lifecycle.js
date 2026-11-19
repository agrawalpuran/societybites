const LEASE_MS = 2 * 60 * 1000;
const MAX_ATTEMPTS = 8;
const BASE_DELAY_MS = 30 * 1000;
const MAX_DELAY_MS = 60 * 60 * 1000;
const STALE_PENDING_MS = 15 * 60 * 1000;

const PROCESSING_AUDIT_ACTIONS = Object.freeze([
  "EVENT_PROCESSED",
  "EVENT_SKIPPED",
  "EVENT_FAILED",
  "EVENT_DEAD",
  "EVENT_RECOVERED",
]);

function backoffMs(attempts) {
  const delay = BASE_DELAY_MS * 2 ** Math.max(0, attempts - 1);
  return Math.min(delay, MAX_DELAY_MS);
}

function isDue(event, now) {
  if (!event || (event.status !== "PENDING" && event.status !== "FAILED")) return false;
  if (!event.nextAttemptAt) return true;
  return new Date(event.nextAttemptAt).getTime() <= now.getTime();
}

function leaseExpired(event, now, leaseMs = LEASE_MS) {
  if (!event || event.status !== "PROCESSING" || !event.claimedAt || !event.claimToken) return false;
  return new Date(event.claimedAt).getTime() + leaseMs <= now.getTime();
}

function failureStatus(attempts) {
  return attempts >= MAX_ATTEMPTS ? "DEAD" : "FAILED";
}

module.exports = {
  BASE_DELAY_MS,
  LEASE_MS,
  MAX_ATTEMPTS,
  MAX_DELAY_MS,
  PROCESSING_AUDIT_ACTIONS,
  STALE_PENDING_MS,
  backoffMs,
  failureStatus,
  isDue,
  leaseExpired,
};
