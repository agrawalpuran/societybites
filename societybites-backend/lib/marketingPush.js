const prisma = require("./prisma");
const { broadcastMarketing } = require("../utils/notifications");

const LAST_SENT_KEY = "marketing_push_last_sent_at";
/** One marketing broadcast per rolling week. */
const INTERVAL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_TITLE = 80;
const MAX_BODY = 160;

function computeCooldownStatus(lastSentAt, now = new Date(), intervalMs = INTERVAL_MS) {
  const last =
    lastSentAt instanceof Date
      ? lastSentAt
      : lastSentAt
        ? new Date(lastSentAt)
        : null;
  const lastValid = last && !Number.isNaN(last.getTime()) ? last : null;
  if (!lastValid) {
    return {
      canSend: true,
      lastSentAt: null,
      nextAllowedAt: null,
      remainingMs: 0,
    };
  }
  const next = new Date(lastValid.getTime() + intervalMs);
  const remainingMs = Math.max(0, next.getTime() - now.getTime());
  return {
    canSend: remainingMs === 0,
    lastSentAt: lastValid.toISOString(),
    nextAllowedAt: next.toISOString(),
    remainingMs,
  };
}

function normalizeCopy(title, body) {
  const t = String(title || "").trim();
  const b = String(body || "").trim();
  if (!t) {
    const err = new Error("Title is required");
    err.status = 400;
    throw err;
  }
  if (!b) {
    const err = new Error("Body is required");
    err.status = 400;
    throw err;
  }
  if (t.length > MAX_TITLE) {
    const err = new Error(`Title must be ${MAX_TITLE} characters or fewer`);
    err.status = 400;
    throw err;
  }
  if (b.length > MAX_BODY) {
    const err = new Error(`Body must be ${MAX_BODY} characters or fewer`);
    err.status = 400;
    throw err;
  }
  return { title: t, body: b };
}

async function getMarketingPushStatus() {
  const [row, activeTokenCount] = await Promise.all([
    prisma.appSetting.findUnique({ where: { key: LAST_SENT_KEY } }),
    prisma.deviceToken.count({ where: { active: true } }),
  ]);
  const cooldown = computeCooldownStatus(row?.value || null);
  return {
    ...cooldown,
    activeTokenCount,
    intervalDays: 7,
  };
}

async function sendMarketingPush({ title, body, adminId }) {
  const copy = normalizeCopy(title, body);
  const status = await getMarketingPushStatus();
  if (!status.canSend) {
    const err = new Error(
      `Marketing push is limited to once per week. Next send after ${status.nextAllowedAt}.`
    );
    err.status = 429;
    err.nextAllowedAt = status.nextAllowedAt;
    throw err;
  }

  const result = await broadcastMarketing(copy);
  const sentAt = new Date().toISOString();
  await prisma.appSetting.upsert({
    where: { key: LAST_SENT_KEY },
    create: { key: LAST_SENT_KEY, value: sentAt },
    update: { value: sentAt },
  });

  if (adminId) {
    await prisma.auditLog.create({
      data: {
        adminId,
        action: "SEND_MARKETING_PUSH",
        target: "marketing_push",
        details: JSON.stringify({
          title: copy.title,
          body: copy.body,
          sent: result.sent,
          failed: result.failed,
          tokenCount: result.tokenCount,
          sentAt,
        }),
      },
    });
  }

  return {
    ...result,
    lastSentAt: sentAt,
    nextAllowedAt: new Date(Date.parse(sentAt) + INTERVAL_MS).toISOString(),
    canSend: false,
    intervalDays: 7,
  };
}

module.exports = {
  LAST_SENT_KEY,
  INTERVAL_MS,
  MAX_TITLE,
  MAX_BODY,
  computeCooldownStatus,
  normalizeCopy,
  getMarketingPushStatus,
  sendMarketingPush,
};
