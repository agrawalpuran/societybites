const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { requireAdmin, requireSuperAdmin } = require("../../../middleware/requireAdmin");
const { readFlags } = require("../configuration/flags");
const { createPrismaRepository } = require("../campaign/prismaRepository");
const service = require("../campaign/service");

function sendError(res, error) {
  if (error && error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  }
  return res.status(500).json({ error: "Incentive request failed" });
}

function createAdminRouter({ repository, loadFlags, requireUser: userGuard, requireAdmin: adminGuard, requireSuperAdmin: superGuard }) {
  const router = express.Router();
  router.use(userGuard, adminGuard);
  router.use((req, res, next) => {
    if (req.method === "GET" || req.method === "HEAD") return next();
    return superGuard(req, res, next);
  });

  function run(statusCode, work) {
    return async (req, res) => {
      try {
        const body = await work(req);
        res.status(statusCode).json(body);
      } catch (error) {
        sendError(res, error);
      }
    };
  }

  function actorId(req) {
    return req.user && req.user.id ? req.user.id : null;
  }

  router.post("/campaigns", run(201, (req) => service.createCampaign(repository, { actorId: actorId(req), body: req.body })));
  router.post("/campaigns/:id/duplicate", run(201, (req) => service.duplicateCampaign(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.get("/campaigns", run(200, () => service.listCampaigns(repository)));
  router.get("/campaigns/:id", run(200, (req) => service.getCampaign(repository, req.params.id)));
  router.patch("/campaigns/:id", run(200, (req) => service.updateCampaign(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.get("/campaigns/:id/versions", run(200, (req) => service.listVersions(repository, req.params.id)));
  router.get("/campaigns/:id/versions/:versionId", run(200, (req) => service.getVersion(repository, req.params.id, req.params.versionId)));
  router.put("/campaigns/:id/audience", run(200, (req) => service.setAudiences(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.put("/campaigns/:id/triggers", run(200, (req) => service.setTriggers(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.put("/campaigns/:id/rules", run(200, (req) => service.setRules(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.put("/campaigns/:id/rewards", run(200, (req) => service.setRewards(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.put("/campaigns/:id/budget", run(200, (req) => service.setBudget(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.put("/campaigns/:id/referral-policy", run(200, (req) => service.setReferralPolicy(repository, { campaignId: req.params.id, actorId: actorId(req), body: req.body })));
  router.post(
    "/campaigns/:id/simulate",
    run(200, (req) =>
      service.simulate(repository, {
        campaignId: req.params.id,
        versionId: req.body && req.body.versionId,
        attributes: req.body && req.body.attributes,
      })
    )
  );

  router.post("/campaigns/:id/activate", run(200, async (req) => {
    const flags = await loadFlags();
    return service.changeStatus(repository, { campaignId: req.params.id, actorId: actorId(req), to: "ACTIVATE", flags });
  }));
  router.post("/campaigns/:id/pause", run(200, (req) => service.changeStatus(repository, { campaignId: req.params.id, actorId: actorId(req), to: "PAUSED" })));
  router.post("/campaigns/:id/terminate", run(200, (req) => service.changeStatus(repository, { campaignId: req.params.id, actorId: actorId(req), to: "TERMINATED" })));
  router.post("/campaigns/:id/complete", run(200, (req) => service.changeStatus(repository, { campaignId: req.params.id, actorId: actorId(req), to: "COMPLETED" })));
  router.post("/campaigns/:id/expire", run(200, (req) => service.changeStatus(repository, { campaignId: req.params.id, actorId: actorId(req), to: "EXPIRED" })));

  return router;
}

const router = createAdminRouter({
  repository: createPrismaRepository(prisma),
  loadFlags: () =>
    readFlags({
      loadRows: () => prisma.incentiveSetting.findMany({ select: { key: true, value: true } }),
    }),
  requireUser,
  requireAdmin,
  requireSuperAdmin,
});

module.exports = router;
module.exports.createAdminRouter = createAdminRouter;
