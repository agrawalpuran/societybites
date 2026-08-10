const express = require("express");
const prisma = require("../lib/prisma");
const logger = require("../lib/logger");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { generateOrderNumber } = require("../utils/orderNumber");
const { serializeOrder } = require("../utils/listingSerializer");
const { getPlatformFee } = require("../lib/platformFee");

const router = express.Router();

const VALID_STATUSES = ["pending", "accepted", "preparing", "ready", "picked_up", "completed", "cancelled"];

const TRANSITIONS = {
  pending: ["accepted", "cancelled"],
  accepted: ["preparing", "cancelled"],
  preparing: ["ready"],
  ready: ["picked_up"],
  picked_up: ["completed"],
};

const SELLER_ACTIONS = new Set(["accepted", "preparing", "ready"]);
const BUYER_ACTIONS = new Set(["cancelled", "picked_up", "completed"]);

const TIMESTAMP_FIELDS = {
  accepted: "acceptedAt",
  preparing: "preparingAt",
  ready: "readyAt",
  picked_up: "pickedUpAt",
  completed: "completedAt",
  cancelled: "cancelledAt",
};

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
  reviews: { select: { id: true } },
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
  "/seller/stats",
  requireUser,
  asyncHandler(async (req, res) => {
    const sellerId = req.user.id;
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const startOfWeek = new Date(startOfToday);
    startOfWeek.setDate(startOfWeek.getDate() - startOfWeek.getDay());

    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

    const [
      todayOrders,
      allSellerOrders,
      listings,
      reviews,
      activeListings,
      soldOutListings,
      allTimeCompletedOrders,
      monthCompletedOrders,
      pendingPaymentConfirmations,
    ] = await Promise.all([
      prisma.order.findMany({
        where: {
          items: { some: { listing: { sellerId } } },
          createdAt: { gte: startOfToday },
        },
        include: { items: { include: { listing: true } } },
      }),
      prisma.order.findMany({
        where: {
          items: { some: { listing: { sellerId } } },
          createdAt: { gte: startOfWeek },
        },
        include: { items: { include: { listing: true } } },
      }),
      prisma.listing.count({ where: { sellerId } }),
      prisma.review.findMany({
        where: { listing: { sellerId } },
        select: { rating: true },
      }),
      prisma.listing.count({ where: { sellerId, status: "active" } }),
      prisma.listing.count({ where: { sellerId, status: "sold_out" } }),
      prisma.order.findMany({
        where: {
          items: { some: { listing: { sellerId } } },
          status: "completed",
        },
        include: { items: { include: { listing: true } } },
      }),
      prisma.order.findMany({
        where: {
          items: { some: { listing: { sellerId } } },
          status: "completed",
          completedAt: { gte: startOfMonth },
        },
        include: { items: { include: { listing: true } } },
      }),
      prisma.order.count({
        where: {
          items: { some: { listing: { sellerId } } },
          paymentStatus: "buyer_marked_paid",
        },
      }),
    ]);

    const filterSellerItems = (orders) =>
      orders.reduce((sum, o) => {
        const sellerItems = o.items.filter((i) => i.listing.sellerId === sellerId);
        return sum + sellerItems.reduce((s, i) => s + i.quantity * i.unitPrice, 0);
      }, 0);

    const todayRevenue = filterSellerItems(
      todayOrders.filter((o) => o.status === "completed")
    );
    const weekRevenue = filterSellerItems(
      allSellerOrders.filter((o) => o.status === "completed")
    );

    const statusCounts = {};
    for (const s of VALID_STATUSES) statusCounts[s] = 0;
    for (const o of todayOrders) statusCounts[o.status] = (statusCounts[o.status] || 0) + 1;

    const avgRating = reviews.length > 0
      ? Math.round((reviews.reduce((s, r) => s + r.rating, 0) / reviews.length) * 10) / 10
      : 0;

    const totalRevenue = filterSellerItems(allTimeCompletedOrders);
    const monthRevenue = filterSellerItems(monthCompletedOrders);

    res.json({
      todayOrders: todayOrders.length,
      statusCounts,
      todayRevenue,
      weekRevenue,
      totalRevenue,
      monthRevenue,
      totalListings: listings,
      activeListings,
      soldOutListings,
      totalOrders: allSellerOrders.length,
      avgRating,
      totalReviews: reviews.length,
      pendingPaymentConfirmations,
    });
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
    const { items, paymentMethod = "upi" } = req.body;

    if (!req.user.societyId) {
      return res.status(400).json({
        error: "You must join a society before placing orders",
      });
    }

    const societyId = req.user.societyId;

    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        error: "A non-empty items array is required",
      });
    }

    if (!["upi", "cash"].includes(paymentMethod)) {
      return res.status(400).json({ error: "paymentMethod must be 'upi' or 'cash'" });
    }

    const preparedItems = [];

    for (const item of items) {
      if (!item.listingId) {
        return res.status(400).json({ error: "Each item must have a listingId" });
      }

      const listing = await prisma.listing.findUnique({
        where: { id: item.listingId },
      });

      if (!listing) {
        return res.status(400).json({
          error: `Listing ${item.listingId} not found`,
        });
      }

      if (listing.status !== "active") {
        return res.status(400).json({
          error: `"${listing.name}" is no longer available (${listing.status})`,
        });
      }

      if (listing.sellerId === req.user.id) {
        return res.status(400).json({
          error: "You cannot order your own listing",
        });
      }

      if (listing.societyId !== societyId) {
        return res.status(400).json({
          error: `"${listing.name}" does not belong to this society`,
        });
      }

      if (listing.availableAt && new Date(listing.availableAt) < new Date()) {
        return res.status(400).json({
          error: `"${listing.name}" has expired`,
        });
      }

      const quantity = parseInt(item.quantity, 10);

      if (!quantity || quantity < 1) {
        return res.status(400).json({ error: "Each item needs quantity >= 1" });
      }

      if (quantity > listing.quantity) {
        return res.status(400).json({
          error: `Only ${listing.quantity} portions left for "${listing.name}"`,
        });
      }

      preparedItems.push({ listing, quantity });
    }

    const sellerIds = new Set(preparedItems.map(({ listing }) => listing.sellerId));
    if (sellerIds.size > 1) {
      return res.status(400).json({
        error: "All items in an order must be from the same seller",
      });
    }

    const subtotal = preparedItems.reduce(
      (sum, { listing, quantity }) => sum + listing.price * quantity,
      0
    );
    const platformFee = await getPlatformFee();
    const total = subtotal + platformFee;

    const order = await prisma.$transaction(async (tx) => {
      for (const { listing, quantity } of preparedItems) {
        const updated = await tx.listing.updateMany({
          where: {
            id: listing.id,
            quantity: { gte: quantity },
            status: "active",
          },
          data: {
            quantity: { decrement: quantity },
          },
        });

        if (updated.count === 0) {
          throw new Error(`Insufficient inventory for "${listing.name}". Please refresh and try again.`);
        }

        const refreshed = await tx.listing.findUnique({ where: { id: listing.id } });
        if (refreshed && refreshed.quantity <= 0) {
          await tx.listing.update({
            where: { id: listing.id },
            data: { status: "sold_out" },
          });
        }
      }

      const created = await tx.order.create({
        data: {
          orderNumber: generateOrderNumber(),
          buyerId: req.user.id,
          societyId,
          status: "pending",
          paymentMethod,
          subtotal,
          communityFee: platformFee,
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

      return created;
    });

    logger.info("order", `Created ${order.orderNumber} by ${req.user.phone}`);

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

    if (order.status === "completed" || order.status === "cancelled") {
      return res.status(400).json({
        error: `Cannot modify a ${order.status} order`,
      });
    }

    const allowed = TRANSITIONS[order.status];
    if (!allowed || !allowed.includes(status)) {
      return res.status(400).json({
        error: `Cannot transition from "${order.status}" to "${status}"`,
      });
    }

    if (status === "preparing" && order.status === "accepted") {
      if (order.paymentMethod === "upi" && order.paymentStatus !== "seller_confirmed") {
        return res.status(400).json({
          error: "Payment must be confirmed before preparing",
        });
      }
    }

    if (status === "picked_up" && order.paymentMethod === "upi") {
      if (!order.paymentStatus || order.paymentStatus === "pending" || order.paymentStatus === "buyer_marked_paid") {
        return res.status(400).json({
          error: "Payment must be confirmed before pickup",
        });
      }
    }

    const isBuyer = order.buyerId === req.user.id;
    const isSeller = order.items.some(
      (item) => item.listing.sellerId === req.user.id
    );

    if (!isBuyer && !isSeller) {
      return res.status(403).json({ error: "Not allowed to update this order" });
    }

    if (SELLER_ACTIONS.has(status) && !isSeller) {
      return res.status(403).json({ error: "Only the seller can perform this action" });
    }

    if (BUYER_ACTIONS.has(status) && !isBuyer) {
      return res.status(403).json({ error: "Only the buyer can perform this action" });
    }

    if (status === "cancelled" && !["pending", "accepted"].includes(order.status)) {
      return res.status(400).json({
        error: "Can only cancel before preparation begins",
      });
    }

    const updateData = {
      status,
      ...(TIMESTAMP_FIELDS[status] && { [TIMESTAMP_FIELDS[status]]: new Date() }),
    };

    let updated;

    if (status === "cancelled") {
      updated = await prisma.$transaction(async (tx) => {
        const result = await tx.order.update({
          where: { id: order.id },
          data: { ...updateData, paymentStatus: "failed" },
          include: orderInclude,
        });

        for (const item of order.items) {
          await tx.listing.update({
            where: { id: item.listingId },
            data: {
              quantity: { increment: item.quantity },
              status: "active",
            },
          });
        }

        logger.info("order", `Cancelled ${order.orderNumber} — inventory restored`);
        return result;
      });
    } else {
      updated = await prisma.order.update({
        where: { id: order.id },
        data: updateData,
        include: orderInclude,
      });

      logger.info("order", `${order.orderNumber} → ${status}`);
    }

    res.json(serializeOrder(updated));
  })
);

module.exports = router;
