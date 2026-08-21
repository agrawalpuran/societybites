/**
 * In-memory OTP challenge store (session id only — never the OTP).
 * A new send invalidates the previous 2Factor session for that phone.
 */
const challenges = new Map();

const OTP_TTL_MS = Number(process.env.OTP_TTL_MS) || 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = Number(process.env.OTP_RESEND_COOLDOWN_MS) || 60 * 1000;
const MAX_SENDS_PER_HOUR = Number(process.env.OTP_MAX_SENDS_PER_HOUR) || 5;
const MAX_VERIFY_ATTEMPTS = Number(process.env.OTP_MAX_VERIFY_ATTEMPTS) || 5;

function prune(phone) {
  const row = challenges.get(phone);
  if (!row) return;
  if (Date.now() > row.expiresAt) challenges.delete(phone);
}

function get(phone) {
  prune(phone);
  return challenges.get(phone) || null;
}

function canSend(phone) {
  const now = Date.now();
  const row = challenges.get(phone);
  if (!row) return { ok: true };

  if (now - row.lastSentAt < RESEND_COOLDOWN_MS) {
    const waitSec = Math.ceil((RESEND_COOLDOWN_MS - (now - row.lastSentAt)) / 1000);
    return {
      ok: false,
      status: 429,
      error: `Please wait ${waitSec}s before requesting another OTP`,
    };
  }

  const hourAgo = now - 60 * 60 * 1000;
  const recentSends = (row.sendTimestamps || []).filter((t) => t > hourAgo);
  if (recentSends.length >= MAX_SENDS_PER_HOUR) {
    return {
      ok: false,
      status: 429,
      error: "Too many OTP requests for this number. Try again later.",
    };
  }

  return { ok: true };
}

function saveSend(phone, sessionId) {
  const now = Date.now();
  const prev = challenges.get(phone);
  const hourAgo = now - 60 * 60 * 1000;
  const sendTimestamps = (prev?.sendTimestamps || []).filter((t) => t > hourAgo);
  sendTimestamps.push(now);

  challenges.set(phone, {
    sessionId,
    expiresAt: now + OTP_TTL_MS,
    attempts: 0,
    lastSentAt: now,
    sendTimestamps,
  });
}

function recordAttempt(phone) {
  const row = get(phone);
  if (!row) return null;
  row.attempts += 1;
  challenges.set(phone, row);
  return row;
}

function consume(phone) {
  challenges.delete(phone);
}

function tooManyAttempts(row) {
  return row.attempts >= MAX_VERIFY_ATTEMPTS;
}

module.exports = {
  get,
  canSend,
  saveSend,
  recordAttempt,
  consume,
  tooManyAttempts,
};
