const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const {
  listBuyerAddresses,
  addBuyerAddress,
  selectBuyerAddress,
  deleteBuyerAddress,
} = require("../lib/buyerAddresses");

const router = express.Router();

router.get(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    res.json(await listBuyerAddresses(req.user));
  })
);

router.post(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    res.status(201).json(await addBuyerAddress(req.user, req.body || {}));
  })
);

router.post(
  "/:id/select",
  requireUser,
  asyncHandler(async (req, res) => {
    res.json(await selectBuyerAddress(req.user, req.params.id));
  })
);

router.delete(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    res.json(await deleteBuyerAddress(req.user, req.params.id));
  })
);

module.exports = router;
