const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { proroutingConfig } = require("../lib/delivery/proroutingClient");
const {
  webhookTokensEqual,
  applyProroutingWebhook,
} = require("../lib/delivery/deliveryService");
const logger = require("../lib/logger");

const router = express.Router();

router.post(
  "/prorouting/:token",
  asyncHandler(async (req, res) => {
    const expected = proroutingConfig().webhookToken;
    if (!webhookTokensEqual(req.params.token, expected)) {
      return res.status(401).json({ error: "Invalid token" });
    }
    try {
      await applyProroutingWebhook(req.body || {});
    } catch (error) {
      logger.error("delivery", `webhook: ${error.message}`);
    }
    res.status(200).json({ ok: true });
  })
);

module.exports = router;
