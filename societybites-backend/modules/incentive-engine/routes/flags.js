const express = require("express");
const prisma = require("../../../lib/prisma");
const { requireUser } = require("../../../middleware/requireUser");
const { readFlagState } = require("../configuration/flags");

function createFlagsRouter({ loadRows, requireUser: guard }) {
  const router = express.Router();
  router.get("/flags", guard, async (req, res, next) => {
    try {
      res.json(await readFlagState({ loadRows }));
    } catch (err) {
      next(err);
    }
  });
  return router;
}

const router = createFlagsRouter({
  requireUser,
  loadRows: () =>
    prisma.incentiveSetting.findMany({
      select: { key: true, value: true },
    }),
});

module.exports = router;
module.exports.createFlagsRouter = createFlagsRouter;
