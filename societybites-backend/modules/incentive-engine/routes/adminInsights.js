const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { requireAdmin, requireSuperAdmin } = require("../../../middleware/requireAdmin");
const reports = require("../analytics/query");

function sendError(res, error) {
  if (error && error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  }
  console.error("[incentive-insights]", error);
  return res.status(500).json({ error: "Incentive request failed" });
}

function createInsightsRouter({
  client = prisma,
  load = reports,
  requireUser: userGuard,
  requireAdmin: adminGuard,
  requireSuperAdmin: superGuard,
} = {}) {
  const router = express.Router();
  router.use(userGuard, adminGuard);
  router.use((req, res, next) => {
    if (req.method === "GET" || req.method === "HEAD") return next();
    return superGuard(req, res, next);
  });

  function run(work) {
    return async (req, res) => {
      try {
        res.json(await work(req));
      } catch (error) {
        sendError(res, error);
      }
    };
  }

  router.get("/campaigns/:id/performance", run((req) => load.performance(client, {
    campaignId: req.params.id,
    query: req.query,
  })));
  router.get("/referral-analytics", run((req) => load.referralAnalytics(client, { query: req.query })));
  router.get("/referral-leaderboard", run(async (req) => {
    const rows = await load.leaderboard(client, {
      campaignId: req.query.campaignId,
      acquisitionKind: req.query.audience,
    });
    return {
      leaders: rows.map((row) => ({
        displayName: row.displayName,
        qualified: row.qualified,
        acquisitionKind: row.acquisitionKind,
        userId: row.userId,
      })),
    };
  }));
  router.get("/reward-report", run((req) => load.rewardReport(client, { query: req.query })));
  router.get("/audit", run((req) => load.auditPage(client, { query: req.query })));
  router.get("/risk", run((req) => load.risk(client, { query: req.query })));
  return router;
}

const router = createInsightsRouter({
  requireUser,
  requireAdmin,
  requireSuperAdmin,
});

module.exports = router;
module.exports.createInsightsRouter = createInsightsRouter;
