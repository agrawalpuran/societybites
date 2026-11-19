const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { requireAdmin, requireSuperAdmin } = require("../../../middleware/requireAdmin");
const {
  approveReferral,
  disqualifyReferral,
  expireDueReferrals,
  reconcileReferral,
  rejectReferral,
} = require("../referrals/qualify");

function sendError(res, error) {
  if (error && error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  }
  console.error("[incentive-referrals]", error);
  return res.status(500).json({ error: "Incentive request failed" });
}

function presentAdmin(row) {
  return {
    id: row.id,
    codeId: row.codeId,
    campaignId: row.campaignId,
    campaignVersionId: row.campaignVersionId,
    referrerUserId: row.referrerUserId,
    referredUserId: row.referredUserId,
    acquisitionKind: row.acquisitionKind,
    status: row.status,
    attributedAt: row.attributedAt,
    windowEndsAt: row.windowEndsAt,
    sellerEnabledAt: row.sellerEnabledAt,
    listingId: row.listingId,
    listingPublishedAt: row.listingPublishedAt,
    qualifyingOrderId: row.qualifyingOrderId,
    qualifyingOrderAt: row.qualifyingOrderAt,
    qualifiedAt: row.qualifiedAt,
    disqualifyReason: row.disqualifyReason,
  };
}

function createPrismaReferralAdmin(prismaClient) {
  return {
    async list(query) {
      const where = {};
      if (query.status) where.status = String(query.status);
      if (query.acquisitionKind) where.acquisitionKind = String(query.acquisitionKind);
      if (query.campaignId) where.campaignId = String(query.campaignId);
      return prismaClient.incentiveReferral.findMany({ where, orderBy: { attributedAt: "desc" }, take: 100 });
    },
    get: (id) => prismaClient.incentiveReferral.findUnique({ where: { id } }),
    approve: (input) => prismaClient.$transaction((tx) => approveReferral(tx, input)),
    reject: (input) => prismaClient.$transaction((tx) => rejectReferral(tx, input)),
    disqualify: (input) => prismaClient.$transaction((tx) => disqualifyReferral(tx, input)),
    expireDue: (input) => prismaClient.$transaction((tx) => expireDueReferrals(tx, input)),
    async reconcile(input) {
      return prismaClient.$transaction(async (tx) => {
        const rows = await tx.incentiveReferral.findMany({
          where: { status: { in: ["QUALIFIED", "PENDING_REVIEW"] }, qualifyingOrderId: { not: null } },
          take: 50,
        });
        const reversed = [];
        for (const row of rows) {
          const order = await tx["order"].findUnique({
            where: { id: row.qualifyingOrderId },
            include: { items: { include: { listing: { select: { sellerId: true, societyId: true } } } } },
          });
          const saved = await reconcileReferral(tx, row, { order, now: input.now, actorId: input.actorId });
          if (saved.status !== row.status) reversed.push(saved);
        }
        return reversed;
      });
    },
  };
}

function createAdminReferralsRouter({ admin, requireUser: userGuard, requireAdmin: adminGuard, requireSuperAdmin: superGuard }) {
  const router = express.Router();
  router.use(userGuard, adminGuard);
  router.use((req, res, next) => {
    if (req.method === "GET" || req.method === "HEAD") return next();
    return superGuard(req, res, next);
  });

  function run(work) {
    return async (req, res) => {
      try {
        const body = await work(req);
        res.json(body);
      } catch (error) {
        sendError(res, error);
      }
    };
  }

  router.get("/referrals", run(async (req) => {
    const rows = await admin.list(req.query || {});
    return { referrals: rows.map(presentAdmin) };
  }));
  router.get("/referrals/:id", run(async (req) => {
    const row = await admin.get(req.params.id);
    if (!row) {
      const error = new Error("Referral not found");
      error.statusCode = 404;
      throw error;
    }
    return presentAdmin(row);
  }));
  router.post("/referrals/:id/approve", run((req) => admin.approve({ id: req.params.id, actorId: req.user.id }).then(presentAdmin)));
  router.post("/referrals/:id/reject", run((req) => admin.reject({
    id: req.params.id,
    actorId: req.user.id,
    reason: req.body && req.body.reason,
  }).then(presentAdmin)));
  router.post("/referrals/:id/disqualify", run((req) => admin.disqualify({
    id: req.params.id,
    actorId: req.user.id,
    reason: req.body && req.body.reason,
  }).then(presentAdmin)));
  router.post("/referrals/expire-due", run(async (req) => {
    const rows = await admin.expireDue({ actorId: req.user.id, now: new Date() });
    return { expired: rows.map(presentAdmin) };
  }));
  router.post("/referrals/reconcile", run(async (req) => {
    const rows = await admin.reconcile({ actorId: req.user.id, now: new Date() });
    return { reversed: rows.map(presentAdmin) };
  }));
  return router;
}

const router = createAdminReferralsRouter({
  admin: createPrismaReferralAdmin(prisma),
  requireUser,
  requireAdmin,
  requireSuperAdmin,
});

module.exports = router;
module.exports.createAdminReferralsRouter = createAdminReferralsRouter;
