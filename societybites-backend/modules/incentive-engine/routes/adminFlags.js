const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { requireSuperAdmin } = require("../../../middleware/requireAdmin");
const { setWritableFlag } = require("../configuration/flags");

function sendError(res, error) {
  if (error && error.code === "P2021") {
    return res.status(503).json({
      error: "Incentive settings are not on this database.",
      code: "INCENTIVE_TABLES_MISSING",
    });
  }
  if (error && error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.code ? { code: error.code } : {}),
    });
  }
  console.error("[incentive-flags]", error);
  return res.status(500).json({ error: "Incentive request failed" });
}

function createAdminFlagsRouter({
  writeFlag = (input) => setWritableFlag(prisma, input),
  requireUser: userGuard = requireUser,
  requireSuperAdmin: superGuard = requireSuperAdmin,
} = {}) {
  const router = express.Router();
  router.put("/flags", userGuard, superGuard, async (req, res) => {
    try {
      const body = req.body || {};
      const flags = await writeFlag({
        actorId: req.user && req.user.id,
        key: body.key,
        enabled: body.enabled,
      });
      res.json(flags);
    } catch (error) {
      sendError(res, error);
    }
  });
  return router;
}

module.exports = createAdminFlagsRouter();
module.exports.createAdminFlagsRouter = createAdminFlagsRouter;
