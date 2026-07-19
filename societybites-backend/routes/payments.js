const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { serializeOrder } = require("../utils/listingSerializer");

const router = express.Router();

const orderInclude = {
  items: {
    include: {
      listing: {
        include: {
          seller: { include: { flat: true } },
          reviews: { select: { rating: true } },
        },
      },
    },
  },
};

router.post(
  "/:orderId/mark-paid",
  requireUser,
  asyncHandler(async (req, res) => {
    const { upiTransactionRef } = req.body || {};

    const order = await prisma.order.findUnique({
      where: { id: req.params.orderId },
      include: orderInclude,
    });

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    if (order.buyerId !== req.user.id) {
      return res.status(403).json({ error: "Only the buyer can mark payment" });
    }

    if (order.status !== "accepted") {
      return res.status(400).json({ error: "Order must be in accepted status" });
    }

    if (order.paymentStatus !== "pending") {
      return res.status(400).json({ error: "Payment has already been marked" });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: {
        paymentStatus: "buyer_marked_paid",
        buyerMarkedPaidAt: new Date(),
        ...(upiTransactionRef && { upiTransactionRef }),
      },
      include: orderInclude,
    });

    res.json(serializeOrder(updated));
  })
);

router.post(
  "/:orderId/confirm",
  requireUser,
  asyncHandler(async (req, res) => {
    const order = await prisma.order.findUnique({
      where: { id: req.params.orderId },
      include: orderInclude,
    });

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    const isSeller = order.items.some(
      (item) => item.listing.sellerId === req.user.id
    );

    if (!isSeller) {
      return res.status(403).json({ error: "Only the seller can confirm payment" });
    }

    if (order.paymentStatus !== "buyer_marked_paid") {
      return res.status(400).json({ error: "Payment has not been marked by buyer" });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: {
        paymentStatus: "seller_confirmed",
        sellerConfirmedPaidAt: new Date(),
        status: "preparing",
        preparingAt: new Date(),
      },
      include: orderInclude,
    });

    console.log(`[PAYMENT] Confirmed for ${order.orderNumber} by seller ${req.user.phone}`);

    res.json(serializeOrder(updated));
  })
);

router.get(
  "/:orderId",
  requireUser,
  asyncHandler(async (req, res) => {
    const order = await prisma.order.findUnique({
      where: { id: req.params.orderId },
      include: orderInclude,
    });

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    const isBuyer = order.buyerId === req.user.id;
    const isSeller = order.items.some(
      (item) => item.listing.sellerId === req.user.id
    );

    if (!isBuyer && !isSeller) {
      return res.status(403).json({ error: "Not allowed to view payment info" });
    }

    const seller = order.items[0]?.listing?.seller;

    res.json({
      paymentStatus: order.paymentStatus || "pending",
      paymentMethod: order.paymentMethod,
      total: order.total,
      buyerMarkedPaidAt: order.buyerMarkedPaidAt || null,
      sellerConfirmedPaidAt: order.sellerConfirmedPaidAt || null,
      upiTransactionRef: order.upiTransactionRef || null,
      sellerUpiId: seller?.upiId || null,
      sellerUpiDisplayName: seller?.upiDisplayName || null,
    });
  })
);

module.exports = router;
