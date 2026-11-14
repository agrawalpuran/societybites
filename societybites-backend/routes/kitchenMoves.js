const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const {
  cancelMyKitchenMove,
  getMyKitchenMove,
  submitKitchenMove,
} = require("../lib/kitchenMove");

const router = express.Router();

router.get(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    res.json(await getMyKitchenMove(req.user));
  })
);

router.post(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const move = await submitKitchenMove(req.user, req.body || {});
    res.status(201).json({ move });
  })
);

router.post(
  "/cancel",
  requireUser,
  asyncHandler(async (req, res) => {
    const move = await cancelMyKitchenMove(req.user);
    res.json({ move });
  })
);

module.exports = router;
