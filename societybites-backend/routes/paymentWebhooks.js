const express = require("express");
const { asyncHandler } = require("../utils/asyncHandler");
const { verifyCashfreeSignature } = require("../lib/payments/cashfreeSignature");
const { cashfreeConfig } = require("../lib/payments/cashfreeClient");
const { applyCashfreeWebhook } = require("../lib/payments/paymentService");
const { notifyPaymentConfirmed, flushNotification } = require("../utils/notifications");

const router = express.Router();

router.post(
  "/cashfree",
  asyncHandler(async (req, res) => {
    const config = cashfreeConfig();
    const rawBody =
      typeof req.rawBody === "string" && req.rawBody.length
        ? req.rawBody
        : JSON.stringify(req.body || {});
    const verified = verifyCashfreeSignature({
      rawBody,
      timestamp: req.get("x-webhook-timestamp"),
      signature: req.get("x-webhook-signature"),
      secret: config.clientSecret,
    });
    if (!verified) {
      return res.status(401).json({ error: "Invalid signature" });
    }
    const result = await applyCashfreeWebhook(req.body || {});
    if (result && result.paidNow && result.order) {
      void flushNotification(notifyPaymentConfirmed(result.order));
    }
    res.json({ ok: true });
  })
);

module.exports = router;
