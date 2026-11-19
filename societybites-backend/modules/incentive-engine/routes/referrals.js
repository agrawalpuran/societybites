const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { rateLimit } = require("../../../middleware/rateLimit");
const { readFlags } = require("../configuration/flags");
const {
  createReferralCode,
  listReferralCodes,
  previewReferralCode,
} = require("../referrals/codes");
const { claimReferral, createPrismaReferralDb, presentReferral } = require("../referrals/attribute");
const { qualificationNote } = require("../analytics/report");

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

function createPrismaReferralRepository(prismaClient) {
  return {
    readFlags: () =>
      readFlags({
        loadRows: () => prismaClient.incentiveSetting.findMany({ select: { key: true, value: true } }),
      }),
    findCampaign: (id) => prismaClient.incentiveCampaign.findUnique({ where: { id } }),
    findVersion: (id) => prismaClient.incentiveCampaignVersion.findUnique({ where: { id } }),
    findCodeByOwner: (userId, audience, scopeKey) =>
      prismaClient.incentiveReferralCode.findUnique({
        where: { userId_audience_scopeKey: { userId, audience, scopeKey } },
      }),
    findCodeByValue: (code) => prismaClient.incentiveReferralCode.findUnique({ where: { code } }),
    listCodes: (userId) =>
      prismaClient.incentiveReferralCode.findMany({
        where: { userId },
        orderBy: { createdAt: "asc" },
      }),
    insertCode: (data) => prismaClient.incentiveReferralCode.create({ data }),
  };
}

function displayName(names, id) {
  const found = (names || []).find((row) => row.id === id);
  return found && found.name ? found.name : "New member";
}

function presentForCaller(row, callerId, names) {
  const otherId = row.referrerUserId === callerId ? row.referredUserId : row.referrerUserId;
  return {
    id: row.id,
    role: row.referrerUserId === callerId ? "referrer" : "referred",
    acquisitionKind: row.acquisitionKind,
    status: row.status,
    attributedAt: new Date(row.attributedAt).toISOString(),
    windowEndsAt: row.windowEndsAt ? new Date(row.windowEndsAt).toISOString() : null,
    sellerActivated: Boolean(row.sellerEnabledAt),
    listingPublished: Boolean(row.listingId),
    orderQualified: Boolean(row.qualifyingOrderId),
    displayName: displayName(names, otherId),
    qualificationNote: qualificationNote(row),
  };
}

function createReferralsRouter({
  repository,
  referrals,
  requireUser: userGuard,
  previewLimit,
} = {}) {
  const router = express.Router();
  const limit = previewLimit || rateLimit({ windowMs: 60000, max: 30 });

  router.get("/referral-codes/preview", limit, async (req, res) => {
    try {
      const body = await previewReferralCode(repository, { code: req.query.code });
      res.json(body);
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/referral-codes", userGuard, async (req, res) => {
    try {
      res.json(await listReferralCodes(repository, { user: req.user }));
    } catch (error) {
      sendError(res, error);
    }
  });

  router.post("/referral-codes", userGuard, async (req, res) => {
    try {
      const result = await createReferralCode(repository, { user: req.user, body: req.body });
      res.status(result.created ? 201 : 200).json(result.code);
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/referrals/leaderboard", userGuard, async (req, res) => {
    try {
      const flags = repository.readFlags ? await repository.readFlags() : null;
      if (!flags || flags.master !== true || flags.referral !== true) {
        return res.status(403).json({ error: "Referral attribution is off", code: "REFERRAL_DISABLED" });
      }
      const query = { ...req.query };
      delete query.userId;
      delete query.referrerUserId;
      const rows = referrals.leaderboard
        ? await referrals.leaderboard({ campaignId: query.campaignId, acquisitionKind: query.audience })
        : [];
      res.json({
        leaders: rows.map((row) => ({
          displayName: row.displayName || "Member",
          qualified: row.qualified || 0,
          acquisitionKind: row.acquisitionKind || null,
        })),
      });
    } catch (error) {
      sendError(res, error);
    }
  });

  router.get("/referrals", userGuard, async (req, res) => {
    try {
      const rows = await referrals.listForUser(req.user.id);
      const ids = [...new Set(rows.flatMap((row) => [row.referrerUserId, row.referredUserId]))];
      const names = ids.length ? await referrals.names(ids) : [];
      res.json({ referrals: rows.map((row) => presentForCaller(row, req.user.id, names)) });
    } catch (error) {
      sendError(res, error);
    }
  });

  router.post("/referrals", userGuard, async (req, res) => {
    try {
      const result = referrals.claim
        ? await referrals.claim({ user: req.user, body: req.body })
        : await claimReferral(referrals, { user: req.user, body: req.body });
      const names = await referrals.names([result.referral.referrerUserId]);
      res.status(result.created ? 201 : 200).json(presentReferral(result.referral, {
        [result.referral.referrerUserId]: displayName(names, result.referral.referrerUserId),
      }));
    } catch (error) {
      sendError(res, error);
    }
  });

  return router;
}

const router = createReferralsRouter({
  repository: createPrismaReferralRepository(prisma),
  referrals: createPrismaReferralDb(prisma),
  requireUser,
});

module.exports = router;
module.exports.createReferralsRouter = createReferralsRouter;
module.exports.createPrismaReferralRepository = createPrismaReferralRepository;
