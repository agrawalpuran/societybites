const crypto = require("crypto");
const prisma = require("./prisma");

const REFRESH_TTL_MS =
  Number(process.env.REFRESH_TOKEN_TTL_MS) || 30 * 24 * 60 * 60 * 1000;

function hashToken(raw) {
  return crypto.createHash("sha256").update(raw).digest("hex");
}

function generateRawToken() {
  return crypto.randomBytes(32).toString("hex");
}

async function issueRefreshToken(userId) {
  const raw = generateRawToken();
  const tokenHash = hashToken(raw);
  const expiresAt = new Date(Date.now() + REFRESH_TTL_MS);

  await prisma.refreshToken.create({
    data: { userId, tokenHash, expiresAt },
  });

  return { refreshToken: raw, expiresAt };
}

async function rotateRefreshToken(raw) {
  const tokenHash = hashToken(raw);
  const existing = await prisma.refreshToken.findUnique({
    where: { tokenHash },
  });

  if (!existing || existing.revokedAt) {
    return { error: "Invalid refresh token", status: 401 };
  }
  if (existing.expiresAt.getTime() <= Date.now()) {
    return { error: "Refresh token expired", status: 401 };
  }

  await prisma.refreshToken.update({
    where: { id: existing.id },
    data: { revokedAt: new Date() },
  });

  const next = await issueRefreshToken(existing.userId);
  return { userId: existing.userId, ...next };
}

async function revokeRefreshToken(raw) {
  if (!raw) return;
  const tokenHash = hashToken(raw);
  await prisma.refreshToken.updateMany({
    where: { tokenHash, revokedAt: null },
    data: { revokedAt: new Date() },
  });
}

module.exports = {
  issueRefreshToken,
  rotateRefreshToken,
  revokeRefreshToken,
};
