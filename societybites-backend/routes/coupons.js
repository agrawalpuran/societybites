const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { validateCoupon } = require("../lib/coupons");

const router = express.Router();

router.post(
  "/validate",
  requireUser,
  asyncHandler(async (req, res) => {
    const body = req.body || {};
    const result = await validateCoupon({
      code: body.code,
      userId: req.user.id,
      orderSubtotal: body.orderSubtotal,
      sellerId: body.sellerId,
    });
    res.json(result);
  })
);

module.exports = router;
