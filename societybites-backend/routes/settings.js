const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { getPlatformFee } = require("../lib/platformFee");

const router = express.Router();

router.get(
  "/",
  asyncHandler(async (_req, res) => {
    const platformFee = await getPlatformFee();
    res.json({ platformFee });
  })
);

module.exports = router;
