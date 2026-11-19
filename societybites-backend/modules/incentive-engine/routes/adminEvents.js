const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { requireAdmin, requireSuperAdmin } = require("../../../middleware/requireAdmin");
const { createPrismaEventRepository } = require("../events/repository");
const {
  getEvent,
  ingestEvent,
  listEvents,
  processDue,
  reconciliationView,
  recoverExpired,
  replayEvent,
} = require("../events/process");
const { backfillProductEvents } = require("../events/productHooks");

function sendError(res, error) {
  if (error && error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  }
  console.error("[incentive-events]", error);
  return res.status(500).json({ error: "Incentive request failed" });
}

function createEventsRouter({
  repository,
  requireUser: userGuard,
  requireAdmin: adminGuard,
  requireSuperAdmin: superGuard,
  backfill,
}) {
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

  router.post("/events", async (req, res) => {
    try {
      const result = await ingestEvent(repository, req.body);
      res.status(result.created ? 201 : 200).json(result);
    } catch (error) {
      sendError(res, error);
    }
  });
  router.get("/events", run(200, (req) => listEvents(repository, req.query)));
  router.get("/events/reconciliation", run(200, () => reconciliationView(repository)));
  router.post("/events/reconciliation/recover", run(200, (req) => recoverExpired(repository, { actorId: actorId(req) })));
  router.post("/events/process-due", async (req, res) => {
    try {
      const result = await processDue(repository, { limit: req.body && req.body.limit });
      if (result.code === "ENGINE_DISABLED") {
        return res.status(403).json({
          error: "Incentive engine is off",
          code: "ENGINE_DISABLED",
          processed: result.processed,
        });
      }
      res.json(result);
    } catch (error) {
      sendError(res, error);
    }
  });
  router.post("/events/backfill", run(200, (req) => {
    const limit = req.body && req.body.limit;
    if (backfill) return backfill({ limit });
    return backfillProductEvents(prisma, { limit });
  }));
  router.get("/events/:id", run(200, (req) => getEvent(repository, req.params.id)));
  router.post("/events/:id/replay", run(200, (req) => replayEvent(repository, { id: req.params.id, actorId: actorId(req) })));

  return router;
}

const router = createEventsRouter({
  repository: createPrismaEventRepository(prisma),
  requireUser,
  requireAdmin,
  requireSuperAdmin,
});

module.exports = router;
module.exports.createEventsRouter = createEventsRouter;
