const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { getKitchenBySlug } = require("../lib/storefront");

const router = express.Router();

// GET /public/kitchens/:slug — branded kitchen site (no auth)
router.get(
  "/kitchens/:slug",
  asyncHandler(async (req, res) => {
    const payload = await getKitchenBySlug(req.params.slug);
    res.json(payload);
  })
);

module.exports = router;
