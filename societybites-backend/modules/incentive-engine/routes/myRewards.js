const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { listOwnHistory, listOwnRewards, listVisibleOffers } = require("../rewards/read");

function sendError(res, error) {
  if (error && error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  }
  console.error("[incentive-my-rewards]", error);
  return res.status(500).json({ error: "Incentive request failed" });
}

function createMyRewardsRouter({
  prisma: prismaClient = prisma,
  requireUser: userGuard = requireUser,
} = {}) {
  const router = express.Router();

  router.get("/offers", userGuard, async (req, res) => {
    try {
      const role = req.user && req.user.role === "seller" ? "seller" : "buyer";
      res.json(await listVisibleOffers(prismaClient, { role }));
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/rewards/history", userGuard, async (req, res) => {
    try {
      const query = { ...(req.query || {}) };
      delete query.userId;
      delete query.recipientUserId;
      res.json(await listOwnHistory(prismaClient, req.user && req.user.id, query));
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/rewards", userGuard, async (req, res) => {
    try {
      const query = { ...(req.query || {}) };
      delete query.userId;
      delete query.recipientUserId;
      res.json(await listOwnRewards(prismaClient, req.user && req.user.id, query));
    } catch (error) {
      sendError(res, error);
    }
  });

  return router;
}

module.exports = createMyRewardsRouter();
module.exports.createMyRewardsRouter = createMyRewardsRouter;
