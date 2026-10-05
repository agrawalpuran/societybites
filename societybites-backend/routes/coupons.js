const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { validateCoupon } = require("../lib/coupons");

const router = express.Router();

router.post(
  "/validate",
  requireUser,
  asyncHandler(async (req, res) => {
    const result = await validateCoupon({
      code: req.body && req.body.code,
      userId: req.user.id,
      orderSubtotal: req.body && req.body.orderSubtotal,
    });
    res.json(result);
  })
);

module.exports = router;
