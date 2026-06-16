const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { generateOrderNumber } = require("../utils/orderNumber");
const { serializeOrder } = require("../utils/listingSerializer");

const router = express.Router();

const COMMUNITY_FEE = 10;
const VALID_STATUSES = ["ordered", "preparing", "ready", "completed", "cancelled"];

const orderInclude = {
  items: {
    include: {
      listing: {
        include: {
          seller: { include: { flat: true } },
        },
      },
    },
  },
};

router.get(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const { role = "buyer", status } = req.query;

    if (role === "seller") {
      const orders = await prisma.order.findMany({
        where: {
          items: {
            some: {
              listing: { sellerId: req.user.id },
            },
          },
          ...(status && { status: String(status) }),
        },
        include: orderInclude,
        orderBy: { createdAt: "desc" },
      });

      return res.json(orders.map(serializeOrder));
    }

    const orders = await prisma.order.findMany({
      where: {
        buyerId: req.user.id,
        ...(status && { status: String(status) }),
      },
      include: orderInclude,
      orderBy: { createdAt: "desc" },
    });

    res.json(orders.map(serializeOrder));
  })
);

router.get(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
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
      return res.status(403).json({ error: "Not allowed to view this order" });
    }

    res.json(serializeOrder(order));
  })
);

router.post(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const { societyId, items, paymentMethod = "upi" } = req.body;

    if (!societyId || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        error: "societyId and a non-empty items array are required",
      });
    }

    const society = await prisma.society.findUnique({
      where: { id: societyId },
    });

    if (!society) {
      return res.status(404).json({ error: "Society not found" });
    }

    const preparedItems = [];

    for (const item of items) {
      const listing = await prisma.listing.findUnique({
        where: { id: item.listingId },
      });

      if (!listing || listing.status !== "active") {
        return res.status(400).json({
          error: `Listing ${item.listingId} is not available`,
        });
      }

      if (listing.societyId !== societyId) {
        return res.status(400).json({
          error: `Listing ${item.listingId} does not belong to this society`,
        });
      }

      const quantity = parseInt(item.quantity, 10);

      if (!quantity || quantity < 1) {
        return res.status(400).json({ error: "Each item needs quantity >= 1" });
      }

      if (quantity > listing.quantity) {
        return res.status(400).json({
          error: `Only ${listing.quantity} portions left for ${listing.name}`,
        });
      }

      preparedItems.push({ listing, quantity });
    }

    const subtotal = preparedItems.reduce(
      (sum, { listing, quantity }) => sum + listing.price * quantity,
      0
    );
    const total = subtotal + COMMUNITY_FEE;

    const order = await prisma.$transaction(async (tx) => {
      const created = await tx.order.create({
        data: {
          orderNumber: generateOrderNumber(),
          buyerId: req.user.id,
          societyId,
          paymentMethod,
          subtotal,
          communityFee: COMMUNITY_FEE,
          total,
          items: {
            create: preparedItems.map(({ listing, quantity }) => ({
              listingId: listing.id,
              quantity,
              unitPrice: listing.price,
            })),
          },
        },
        include: orderInclude,
      });

      for (const { listing, quantity } of preparedItems) {
        const remaining = listing.quantity - quantity;

        await tx.listing.update({
          where: { id: listing.id },
          data: {
            quantity: remaining,
            status: remaining <= 0 ? "sold_out" : listing.status,
          },
        });
      }

      return created;
    });

    res.status(201).json(serializeOrder(order));
  })
);

router.patch(
  "/:id/status",
  requireUser,
  asyncHandler(async (req, res) => {
    const { status } = req.body;

    if (!status || !VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `status must be one of: ${VALID_STATUSES.join(", ")}`,
      });
    }

    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
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
      return res.status(403).json({ error: "Not allowed to update this order" });
    }

    if (isSeller && !isBuyer && status === "cancelled") {
      return res.status(403).json({ error: "Only the buyer can cancel an order" });
    }

    const updated = await prisma.order.update({
      where: { id: req.params.id },
      data: { status },
      include: orderInclude,
    });

    res.json(serializeOrder(updated));
  })
);

module.exports = router;
