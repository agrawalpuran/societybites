const express = require("express");
const prisma = require("../lib/prisma");
const logger = require("../lib/logger");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { generateOrderNumber } = require("../utils/orderNumber");
const { serializeOrder } = require("../utils/listingSerializer");
const { getPlatformFee } = require("../lib/platformFee");
const { expireListingIfDue } = require("../utils/listingExpiry");
const {
  notifyOrderCreated,
  notifyStatusChange,
  notifyOrderRejected,
  notifyReadyBy,
} = require("../utils/notifications");
const {
  lazyCloseCampaign,
  assertCampaignAcceptsOrders,
  shouldRestoreListingInventory,
} = require("../lib/preorder");

const router = express.Router();

const VALID_STATUSES = [
  "pending",
  "accepted",
  "preparing",
  "ready",
  "picked_up",
  "completed",
  "cancelled",
  "rejected",
];

const REJECT_REASONS = [
  "Food sold out",
  "Unable to prepare today",
  "Kitchen closed",
  "Ingredients unavailable",
  "Other",
];

const REJECTABLE_STATUSES = new Set(["pending", "accepted", "preparing"]);

const TRANSITIONS = {
  pending: ["accepted", "cancelled", "rejected"],
  accepted: ["preparing", "cancelled", "rejected"],
  preparing: ["ready", "rejected"],
  ready: ["picked_up"],
  picked_up: ["completed"],
};

const SELLER_ACTIONS = new Set(["accepted", "preparing", "ready", "rejected"]);
const BUYER_ACTIONS = new Set(["cancelled", "picked_up", "completed"]);

const TIMESTAMP_FIELDS = {
  accepted: "acceptedAt",
  preparing: "preparingAt",
  ready: "readyAt",
  picked_up: "pickedUpAt",
  completed: "completedAt",
  cancelled: "cancelledAt",
  rejected: "rejectedAt",
};

async function restoreReservedInventory(tx, items) {
  for (const item of items) {
    if (!shouldRestoreListingInventory(item.listing)) continue;
    await tx.listing.update({
      where: { id: item.listingId },
      data: {
        quantity: { increment: item.quantity },
        status: "active",
      },
    });
  }
}

const orderInclude = {
  buyer: {
    include: {
      flat: true,
      society: true,
    },
  },
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
    const orderType = req.body.type === "pre_order" ? "pre_order" : "regular";

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

    if (orderType === "regular" && req.body.campaignId) {
      return res.status(400).json({
        error: "Regular orders cannot include a pre-order campaign",
      });
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

      if (orderType === "regular" && listing.campaignId) {
        return res.status(400).json({
          error: "Cannot mix regular listings and pre-order products in one order",
        });
      }
      if (orderType === "pre_order" && !listing.campaignId) {
        return res.status(400).json({
          error: "Cannot mix regular listings and pre-order products in one order",
        });
      }

      const current =
        orderType === "regular"
          ? await expireListingIfDue(prisma, listing)
          : listing;

      if (current.status === "paused") {
        return res.status(400).json({
          error: `"${current.name}" is paused and cannot be ordered`,
        });
      }

      if (orderType === "regular") {
        if (current.status === "expired") {
          return res.status(400).json({
            error: `"${current.name}" has expired and cannot be ordered`,
          });
        }
        if (current.availableAt && new Date(current.availableAt) < new Date()) {
          return res.status(400).json({
            error: `"${current.name}" has expired and cannot be ordered`,
          });
        }
      }

      if (current.status !== "active") {
        return res.status(400).json({
          error: `"${current.name}" is no longer available (${current.status})`,
        });
      }

      const quantity = parseInt(item.quantity, 10);

      if (!quantity || quantity < 1) {
        return res.status(400).json({ error: "Each item needs quantity >= 1" });
      }

      const enforceStock =
        orderType === "regular" || current.inventoryMode === "limited";
      if (enforceStock && quantity > current.quantity) {
        return res.status(409).json({
          error:
            current.quantity === 0
              ? `"${current.name}" is sold out`
              : `Only ${current.quantity} portions are available for "${current.name}".`,
          availableQuantity: current.quantity,
        });
      }

      preparedItems.push({ listing: current, quantity });
    }

    const sellerIds = new Set(preparedItems.map(({ listing }) => listing.sellerId));
    if (sellerIds.size > 1) {
      return res.status(400).json({
        error: "All items in an order must be from the same seller",
      });
    }

    let campaign = null;
    let fulfilmentMethod = null;
    let deliveryCharge = 0;
    let fulfilmentAt = null;
    const fulfilmentNotes =
      typeof req.body.fulfilmentNotes === "string"
        ? req.body.fulfilmentNotes.trim() || null
        : null;

    if (orderType === "pre_order") {
      const campaignId = req.body.campaignId;
      if (!campaignId) {
        return res.status(400).json({ error: "campaignId is required for pre-orders" });
      }

      campaign = await prisma.preOrderCampaign.findUnique({
        where: { id: campaignId },
      });
      if (!campaign) {
        return res.status(404).json({ error: "Pre-order campaign not found" });
      }
      campaign = await lazyCloseCampaign(campaign);

      try {
        assertCampaignAcceptsOrders(campaign);
      } catch (err) {
        return res.status(err.statusCode || 400).json({ error: err.message });
      }

      if (campaign.societyId !== societyId) {
        return res.status(400).json({ error: "Campaign does not belong to this society" });
      }

      const campaignListingIds = new Set(
        preparedItems.map(({ listing }) => listing.campaignId)
      );
      if (campaignListingIds.size !== 1 || !campaignListingIds.has(campaign.id)) {
        return res.status(400).json({
          error: "All pre-order items must belong to the same campaign",
        });
      }

      const campaignSellerIds = new Set(
        preparedItems.map(({ listing }) => listing.sellerId)
      );
      if (!campaignSellerIds.has(campaign.sellerId) || campaignSellerIds.size !== 1) {
        return res.status(400).json({
          error: "All items must belong to the campaign seller",
        });
      }

      fulfilmentMethod = req.body.fulfilmentMethod;
      if (!["pickup", "seller_delivery"].includes(fulfilmentMethod)) {
        return res.status(400).json({
          error: "fulfilmentMethod must be pickup or seller_delivery",
        });
      }
      if (!(campaign.offeredFulfilmentMethods || []).includes(fulfilmentMethod)) {
        return res.status(400).json({
          error: "That fulfilment method is not offered for this campaign",
        });
      }

      deliveryCharge =
        fulfilmentMethod === "seller_delivery"
          ? Number(campaign.defaultDeliveryCharge || 0)
          : 0;
      fulfilmentAt = campaign.fulfilmentAt;
    }

    const subtotal = preparedItems.reduce(
      (sum, { listing, quantity }) => sum + listing.price * quantity,
      0
    );
    const platformFee = await getPlatformFee();
    const total = subtotal + platformFee + deliveryCharge;

    let order;
    try {
      order = await prisma.$transaction(async (tx) => {
        for (const { listing, quantity } of preparedItems) {
          const reserveStock =
            orderType === "regular" || listing.inventoryMode === "limited";
          if (!reserveStock) continue;

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
            const latest = await tx.listing.findUnique({
              where: { id: listing.id },
              select: { quantity: true },
            });
            const available = latest?.quantity ?? 0;
            const err = new Error(
              available === 0
                ? `"${listing.name}" is sold out`
                : `Only ${available} portions are available for "${listing.name}".`
            );
            err.statusCode = 409;
            err.availableQuantity = available;
            throw err;
          }

          const refreshed = await tx.listing.findUnique({ where: { id: listing.id } });
          if (refreshed && refreshed.quantity <= 0) {
            await tx.listing.update({
              where: { id: listing.id },
              data: { status: "sold_out" },
            });
          }
        }

        return tx.order.create({
          data: {
            orderNumber: generateOrderNumber(),
            buyerId: req.user.id,
            societyId,
            type: orderType,
            campaignId: campaign ? campaign.id : null,
            fulfilmentMethod,
            deliveryCharge,
            fulfilmentNotes,
            fulfilmentAt,
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
      });
    } catch (err) {
      if (err.statusCode === 409) {
        return res.status(409).json({
          error: err.message,
          availableQuantity: err.availableQuantity,
        });
      }
      throw err;
    }

    logger.info("order", `Created ${order.orderNumber} by ${req.user.phone}`);

    notifyOrderCreated(order);

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

    if (
      order.status === "completed" ||
      order.status === "cancelled" ||
      order.status === "rejected"
    ) {
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

    if (status === "completed" && order.paymentMethod === "cash") {
      if (order.paymentStatus !== "paid") {
        return res.status(400).json({
          error:
            "Please confirm that payment has been received before completing this order.",
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

    // Buyer or seller may complete after pickup; other actions stay role-gated.
    if (status === "completed") {
      if (!isBuyer && !isSeller) {
        return res.status(403).json({ error: "Not allowed to complete this order" });
      }
    } else if (SELLER_ACTIONS.has(status) && !isSeller) {
      return res.status(403).json({ error: "Only the seller can perform this action" });
    } else if (BUYER_ACTIONS.has(status) && !isBuyer) {
      return res.status(403).json({ error: "Only the buyer can perform this action" });
    }

    if (status === "cancelled" && !["pending", "accepted"].includes(order.status)) {
      return res.status(400).json({
        error: "Can only cancel before preparation begins",
      });
    }

    if (status === "cancelled" && (order.type || "regular") === "pre_order") {
      if (order.campaignId) {
        let campaign = await prisma.preOrderCampaign.findUnique({
          where: { id: order.campaignId },
        });
        if (campaign) {
          campaign = await lazyCloseCampaign(campaign);
          if (new Date() >= new Date(campaign.orderCutoffAt)) {
            return res.status(400).json({
              error: "Pre-orders cannot be cancelled after the cutoff",
            });
          }
        }
      }
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

        await restoreReservedInventory(tx, order.items);

        logger.info("order", `Cancelled ${order.orderNumber} — inventory restored`);
        return result;
      });
    } else if (status === "rejected") {
      return res.status(400).json({
        error: "Use POST /orders/:id/reject to reject an order with a reason",
      });
    } else {
      updated = await prisma.order.update({
        where: { id: order.id },
        data: updateData,
        include: orderInclude,
      });

      logger.info("order", `${order.orderNumber} → ${status}`);
    }

    notifyStatusChange(updated, status);

    res.json(serializeOrder(updated));
  })
);

router.post(
  "/:id/reject",
  requireUser,
  asyncHandler(async (req, res) => {
    const { reason, otherText } = req.body;

    if (!reason || !REJECT_REASONS.includes(reason)) {
      return res.status(400).json({
        error: `reason must be one of: ${REJECT_REASONS.join(", ")}`,
      });
    }

    let rejectReason = reason;
    if (reason === "Other") {
      const text = typeof otherText === "string" ? otherText.trim() : "";
      if (!text) {
        return res.status(400).json({ error: "otherText is required when reason is Other" });
      }
      if (text.length > 200) {
        return res.status(400).json({ error: "otherText must be at most 200 characters" });
      }
      rejectReason = text;
    }

    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: orderInclude,
    });

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    if (!REJECTABLE_STATUSES.has(order.status)) {
      return res.status(400).json({
        error: `Cannot reject an order with status "${order.status}"`,
      });
    }

    const isSeller = order.items.some(
      (item) => item.listing.sellerId === req.user.id
    );

    if (!isSeller) {
      return res.status(403).json({ error: "Only the seller can reject this order" });
    }

    const updated = await prisma.$transaction(async (tx) => {
      const result = await tx.order.update({
        where: { id: order.id },
        data: {
          status: "rejected",
          rejectReason,
          rejectedAt: new Date(),
          rejectedBy: req.user.id,
          paymentStatus:
            order.paymentStatus === "seller_confirmed" ||
            order.paymentStatus === "paid"
              ? order.paymentStatus
              : "failed",
        },
        include: orderInclude,
      });

      await restoreReservedInventory(tx, order.items);

      logger.info(
        "order",
        `Rejected ${order.orderNumber} by ${req.user.phone} — ${rejectReason}`
      );
      return result;
    });

    notifyOrderRejected(updated);

    res.json(serializeOrder(updated));
  })
);

router.patch(
  "/:id/ready-time",
  requireUser,
  asyncHandler(async (req, res) => {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: orderInclude,
    });

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    const isSeller = order.items.some(
      (item) => item.listing.sellerId === req.user.id
    );

    if (!isSeller) {
      return res.status(403).json({
        error: "Only the seller can set a Ready by time for this order",
      });
    }

    if (!["accepted", "preparing"].includes(order.status)) {
      return res.status(400).json({
        error: `Ready by can only be set while the order is accepted or preparing (current: "${order.status}")`,
      });
    }

    const { expectedReadyAt } = req.body;

    // Explicit null / missing key with null clears the estimate.
    if (expectedReadyAt === null) {
      const updated = await prisma.order.update({
        where: { id: order.id },
        data: { expectedReadyAt: null },
        include: orderInclude,
      });
      logger.info("order", `Cleared Ready by for ${order.orderNumber}`);
      notifyReadyBy(updated, true);
      return res.json(serializeOrder(updated));
    }

    if (expectedReadyAt === undefined) {
      return res.status(400).json({
        error: "expectedReadyAt is required (ISO datetime or null to clear)",
      });
    }

    const readyAt = new Date(expectedReadyAt);
    if (Number.isNaN(readyAt.getTime())) {
      return res.status(400).json({ error: "expectedReadyAt must be a valid date" });
    }

    if (readyAt <= new Date()) {
      return res.status(400).json({
        error: "Ready by time must be in the future",
      });
    }

    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { expectedReadyAt: readyAt },
      include: orderInclude,
    });

    logger.info(
      "order",
      `Ready by set for ${order.orderNumber}: ${readyAt.toISOString()}`
    );
    notifyReadyBy(updated, false);
    res.json(serializeOrder(updated));
  })
);

module.exports = router;
