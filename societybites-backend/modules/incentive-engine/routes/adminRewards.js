const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { requireAdmin, requireSuperAdmin } = require("../../../middleware/requireAdmin");
const { effectiveFlags } = require("../configuration/flags");
const { listLedger, overview, presentRewards, reconcileBudget } = require("../rewards/read");
const { approveReward, expireDueRewards, redeemReward, rejectReward } = require("../rewards/approve");
const { notifyIncentiveReward } = require("../../../utils/notifications");

function sendError(res, error) {
  if (error && error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  }
  console.error("[incentive-rewards]", error);
  return res.status(500).json({ error: "Incentive request failed" });
}

function createRewardsRouter({
  prisma: prismaClient = prisma,
  requireUser: userGuard = requireUser,
  requireAdmin: adminGuard = requireAdmin,
  requireSuperAdmin: superGuard = requireSuperAdmin,
} = {}) {
  const router = express.Router();
  router.use(userGuard, adminGuard);
  router.use((req, res, next) => {
    if (req.method === "GET" || req.method === "HEAD") return next();
    return superGuard(req, res, next);
  });

  router.get("/overview", async (req, res) => {
    try {
      res.json(await overview(prismaClient));
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/ledger", async (req, res) => {
    try {
      res.json(await listLedger(prismaClient, req.query || {}));
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/rewards", async (req, res) => {
    try {
      const where = {};
      if (req.query.status) where.status = String(req.query.status);
      if (req.query.recipientUserId) where.recipientUserId = String(req.query.recipientUserId);
      const rows = await prismaClient.incentiveReward.findMany({
        where,
        orderBy: { createdAt: "desc" },
        take: 100,
      });
      res.json({ rewards: await presentRewards(prismaClient, rows) });
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/rewards/reconciliation", async (req, res) => {
    try {
      res.json(await reconcileBudget(prismaClient, req.query.campaignId));
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/rewards/:id", async (req, res) => {
    try {
      const reward = await prismaClient.incentiveReward.findUnique({ where: { id: req.params.id } });
      if (!reward) return res.status(404).json({ error: "Reward not found", code: "REWARD_NOT_FOUND" });
      const entries = await prismaClient.incentiveLedgerEntry.findMany({
        where: { rewardId: reward.id },
        orderBy: { createdAt: "asc" },
      });
      const [presented] = await presentRewards(prismaClient, [reward]);
      res.json({
        reward: presented,
        ledger: entries.map((entry) => ({
          id: entry.id,
          entryType: entry.entryType,
          amount: String(entry.amount),
          reason: entry.reason,
          idempotencyKey: entry.idempotencyKey,
          createdAt: entry.createdAt,
        })),
      });
    } catch (error) {
      sendError(res, error);
    }
  });

  router.post("/rewards/:id/approve", async (req, res) => {
    try {
      const reward = await prismaClient.$transaction((tx) => approveReward(tx, {
        rewardId: req.params.id,
        actorId: req.user.id,
      }));
      if (reward && reward.recorded) {
        notifyIncentiveReward(reward, reward.couponId ? "coupon" : "approved");
      }
      const [presented] = await presentRewards(prismaClient, [reward]);
      res.json({ reward: presented });
    } catch (error) {
      sendError(res, error);
    }
  });

  router.post("/rewards/:id/reject", async (req, res) => {
    try {
      const reward = await prismaClient.$transaction((tx) => rejectReward(tx, {
        rewardId: req.params.id,
        actorId: req.user.id,
        reason: req.body && req.body.reason,
      }));
      if (reward && reward.recorded) notifyIncentiveReward(reward, "rejected");
      const [presented] = await presentRewards(prismaClient, [reward]);
      res.json({ reward: presented });
    } catch (error) {
      sendError(res, error);
    }
  });

  router.post("/rewards/:id/redeem", async (req, res) => {
    try {
      const rows = await prismaClient.incentiveSetting.findMany({ select: { key: true, value: true } });
      const saved = await prismaClient.$transaction((tx) => redeemReward(tx, {
        rewardId: req.params.id,
        amount: req.body && req.body.amount,
        orderId: req.body && req.body.orderId,
        actorId: req.user.id,
        idempotencyKey: req.body && req.body.idempotencyKey,
        flags: effectiveFlags(rows),
      }));
      if (saved && saved.duplicate !== true) notifyIncentiveReward(saved.reward, "redeemed");
      const [presented] = await presentRewards(prismaClient, [saved.reward]);
      res.json({ reward: presented, duplicate: saved.duplicate === true });
    } catch (error) {
      sendError(res, error);
    }
  });

  router.post("/rewards/expire-due", async (req, res) => {
    try {
      const expired = await prismaClient.$transaction((tx) => expireDueRewards(tx, {
        actorId: req.user.id,
      }));
      res.json({ expired: await presentRewards(prismaClient, expired) });
    } catch (error) {
      sendError(res, error);
    }
  });

  return router;
}

module.exports = createRewardsRouter();
module.exports.createRewardsRouter = createRewardsRouter;
