const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { getActiveFestivalBanner } = require("../lib/festivalBanners");

const router = express.Router();

// GET /festival-banners/active — public Home banner (no auth)
router.get(
  "/active",
  asyncHandler(async (_req, res) => {
    const banner = await getActiveFestivalBanner();
    res.json({ banner });
  })
);

module.exports = router;
