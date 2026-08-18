const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const logger = require("../lib/logger");

const router = express.Router();

/**
 * POST /devices/register
 * Body: { token: string, platform?: string }
 * Upserts FCM token for the authenticated user.
 */
router.post(
  "/register",
  requireUser,
  asyncHandler(async (req, res) => {
    const token = typeof req.body?.token === "string" ? req.body.token.trim() : "";
    const platform =
      typeof req.body?.platform === "string" ? req.body.platform.trim().slice(0, 32) : null;

    if (!token || token.length < 20) {
      return res.status(400).json({ error: "token is required" });
    }

    const existing = await prisma.deviceToken.findUnique({ where: { token } });

    if (existing) {
      const updated = await prisma.deviceToken.update({
        where: { token },
        data: {
          userId: req.user.id,
          platform: platform || existing.platform,
          active: true,
          lastSeenAt: new Date(),
        },
      });
      return res.json({ ok: true, id: updated.id });
    }

    const created = await prisma.deviceToken.create({
      data: {
        userId: req.user.id,
        token,
        platform,
        active: true,
        lastSeenAt: new Date(),
      },
    });

    logger.info("devices", `Registered token for user ${req.user.id}`);
    res.status(201).json({ ok: true, id: created.id });
  })
);

/**
 * DELETE /devices
 * Body: { token?: string } — if omitted, deactivates all tokens for the user (logout).
 */
router.delete(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const token = typeof req.body?.token === "string" ? req.body.token.trim() : null;

    if (token) {
      await prisma.deviceToken.updateMany({
        where: { token, userId: req.user.id },
        data: { active: false },
      });
    } else {
      await prisma.deviceToken.updateMany({
        where: { userId: req.user.id, active: true },
        data: { active: false },
      });
    }

    res.json({ ok: true });
  })
);

module.exports = router;
