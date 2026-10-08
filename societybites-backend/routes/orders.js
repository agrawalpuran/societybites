const express = require("express");
const prisma = require("../lib/prisma");
const logger = require("../lib/logger");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { generateOrderNumber } = require("../utils/orderNumber");
const {
  serializeOrder,
  serializeOrderStatusPatch,
} = require("../utils/listingSerializer");
const { loadSellerInsights } = require("../lib/sellerInsights");
const { getPlatformFee } = require("../lib/platformFee");
const { expireListingIfDue } = require("../utils/listingExpiry");
const {
  assertMadeToOrderCapacity,
  isMadeToOrderListing,
  assertRegularOrderAvailabilityMix,
  assertSingleMadeToOrderListingInOrder,
} = require("../lib/listingAvailability");
const {
  assertRecurringOrderable,
  isRecurringReadyNowListing,
  isSameDayHoursListing,
} = require("../lib/recurringAvailability");
const {
  notifyOrderCreated,
  notifyStatusChange,
  notifyOrderRejected,
  notifyReadyBy,
  notifyOrderMessage,
  flushNotification,
} = require("../utils/notifications");
const {
  lazyCloseCampaign,
  assertCampaignAcceptsOrders,
  shouldRestoreListingInventory,
} = require("../lib/preorder");
const {
  authorizeListingForBuyer,
  snapshotRegularFulfilment,
  DELIVERY_REACH,
} = require("../lib/crossSocietyOrder");
const { offersSellerDelivery } = require("../lib/sellerFulfilment");
const { assertSellerKitchenOpen } = require("../lib/kitchenHours");
const {
  assertPaymentMethodAllowed,
  upiBlocksPreparation,
} = require("../lib/sellerPaymentPreference");
const {
  assertOrderParticipant,
  parseMessageBody,
  serializeMessage,
  attachUnreadCounts,
} = require("../lib/orderMessages");
const { buyerCancelDeniedReason } = require("../lib/buyerCancel");
const {
  skipsSellerAcceptance,
  orderSkipsSellerAcceptance,
  sellerCanDecline,
} = require("../lib/orderAcceptance");
const { parseRequestedReadyAt } = require("../lib/orderReadyTime");
const { listSellerOrders } = require("../lib/sellerOrderList");
const {
  attachCouponRedemption,
  reverseCouponForOrder,
  couponErrorMessage,
  money: couponMoney,
} = require("../lib/coupons");
const {
  parseIdempotencyKey,
  findCompletedIdempotentOrder,
  runWithOrderIdempotency,
} = require("../lib/orderIdempotency");

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

const RETIRED_STATUSES = new Set(["preparing", "picked_up"]);

const REJECT_REASONS = [
  "Not available today",
  "Ingredients unavailable",
  "Too many orders",
  "Not enough time",
  "Unable to fulfil by requested date",
  "Other",
];

const BUYER_CANCEL_REASONS = [
  "Changed my mind",
  "Ordered by mistake",
  "No longer needed",
  "Delivery or timing issue",
  "Other",
];

function parseReasonChoice(rawReason, allowedReasons) {
  const trimmed = String(rawReason || "").trim();
  const matched = allowedReasons.includes(trimmed)
    ? trimmed
    : allowedReasons.find((item) => trimmed.startsWith(item)) || "";
  return matched;
}

function formatStoredReason(matchedReason, note) {
  const trimmedNote = String(note || "").trim();
  if (trimmedNote.length > 200) {
    const err = new Error("otherText must be at most 200 characters");
    err.statusCode = 400;
    throw err;
  }
  return trimmedNote ? `${matchedReason}\n${trimmedNote}` : matchedReason;
}

const TRANSITIONS = {
  pending: ["accepted", "cancelled"],
  accepted: ["ready", "cancelled"],
  preparing: ["ready"],
  ready: ["completed"],
  picked_up: ["completed"],
};

const SELLER_ACTIONS = new Set(["accepted", "ready", "completed"]);
const BUYER_ACTIONS = new Set(["cancelled"]);

const TIMESTAMP_FIELDS = {
  accepted: "acceptedAt",
  preparing: "preparingAt",
  ready: "readyAt",
  picked_up: "pickedUpAt",
  completed: "completedAt",
  cancelled: "cancelledAt",
  rejected: "rejectedAt",
};

async function updateOrderIfCurrentStatus(
  client,
  { id, fromStatus, data, reload = true }
) {
  const result = await client.order.updateMany({
    where: { id, status: fromStatus },
    data,
  });
  if (result.count === 0) {
    const err = new Error(
      "Order status has already changed. Refresh and try again."
    );
    err.statusCode = 409;
    throw err;
  }
  if (!reload) return null;
  return client.order.findUnique({
    where: { id },
    include: orderInclude,
  });
}

async function findOrderForUpdate(id) {
  const byId = await prisma.order.findUnique({
    where: { id },
    include: orderInclude,
  });
  if (byId) return byId;
  return prisma.order.findUnique({
    where: { orderNumber: id },
    include: orderInclude,
  });
}

function isOrderSeller(order, userId) {
  return (order.items || []).some(
    (item) => item.listing && item.listing.sellerId === userId
  );
}

async function restoreReservedInventory(tx, items) {
  for (const item of items) {
    if (!shouldRestoreListingInventory(item.listing)) continue;
    if (isRecurringReadyNowListing(item.listing)) continue;
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
          seller: { include: { flat: true, society: true } },
          reviews: { select: { rating: true } },
        },
      },
    },
  },
  reviews: { select: { id: true } },
  couponRedemptions: {
    where: { status: { in: ["APPLIED", "REDEEMED"] } },
    include: { coupon: { select: { code: true } } },
    take: 1,
  },
};

/** Same shape as [orderInclude] but skips per-listing review aggregates on create. */
const orderIncludeForCreate = {
  buyer: orderInclude.buyer,
  items: {
    include: {
      listing: {
        include: {
          seller: { include: { flat: true, society: true } },
        },
      },
    },
  },
  reviews: orderInclude.reviews,
  couponRedemptions: orderInclude.couponRedemptions,
};

router.get(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const { role = "buyer", status, scope } = req.query;

    if (role === "seller") {
      if (scope) {
        const page = await listSellerOrders(prisma, {
          sellerId: req.user.id,
          scope,
          status,
          page: req.query.page,
          limit: req.query.limit,
          include: orderInclude,
        });
        return res.json({
          orders: await attachUnreadCounts(
            prisma,
            page.orders.map(serializeOrder),
            req.user.id
          ),
          hasMore: page.hasMore,
          hasOlder: page.hasOlder,
          pendingCount: page.pendingCount || 0,
          scope: page.scope,
        });
      }

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

      return res.json(
        await attachUnreadCounts(prisma, orders.map(serializeOrder), req.user.id)
      );
    }

    const orders = await prisma.order.findMany({
      where: {
        buyerId: req.user.id,
        ...(status && { status: String(status) }),
      },
      include: orderInclude,
      orderBy: { createdAt: "desc" },
    });

    res.json(
      await attachUnreadCounts(prisma, orders.map(serializeOrder), req.user.id)
    );
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
  "/seller/insights",
  requireUser,
  asyncHandler(async (req, res) => {
    try {
      const insights = await loadSellerInsights(prisma, {
        sellerId: req.user.id,
        preset: req.query.preset,
        from: req.query.from,
        to: req.query.to,
      });
      res.json(insights);
    } catch (err) {
      if (err.statusCode) {
        return res.status(err.statusCode).json({ error: err.message });
      }
      throw err;
    }
  })
);

router.get(
  "/:id/messages",
  requireUser,
  asyncHandler(async (req, res) => {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: {
        items: { select: { listing: { select: { sellerId: true } } } },
      },
    });

    assertOrderParticipant(order, req.user.id);

    const rows = await prisma.message.findMany({
      where: { orderId: order.id },
      orderBy: { createdAt: "asc" },
    });

    res.json(rows.map((row) => serializeMessage(row, order)));

    try {
      await prisma.message.updateMany({
        where: {
          orderId: order.id,
          senderId: { not: req.user.id },
          readAt: null,
        },
        data: { readAt: new Date() },
      });
    } catch (_) {
      // Messages already returned; unread badges catch up on the next poll.
    }
  })
);

router.post(
  "/:id/messages",
  requireUser,
  asyncHandler(async (req, res) => {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: {
        items: { select: { listing: { select: { sellerId: true } } } },
      },
    });

    assertOrderParticipant(order, req.user.id);
    const message = parseMessageBody(req.body && req.body.message);

    const created = await prisma.message.create({
      data: {
        orderId: order.id,
        senderId: req.user.id,
        message,
      },
    });

    res.status(201).json(serializeMessage(created, order));

    await flushNotification(notifyOrderMessage(order, req.user.id));
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

    res.json(
      await attachUnreadCounts(prisma, [serializeOrder(order)], req.user.id).then(
        (rows) => rows[0]
      )
    );
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

    const idempotencyKey = parseIdempotencyKey(req);
    const replayOrder = await findCompletedIdempotentOrder(
      prisma,
      req.user.id,
      idempotencyKey,
      orderIncludeForCreate
    );
    if (replayOrder) {
      return res.status(201).json(serializeOrder(replayOrder));
    }

    if (orderType === "regular" && req.body.campaignId) {
      return res.status(400).json({
        error: "Regular orders cannot include a pre-order campaign",
      });
    }

    const preparedItems = [];
    const kitchenChecked = new Set();
    const listingAccessCache = new Map();

    const listingIds = items.map((item) => item.listingId).filter(Boolean);
    const listingsById = new Map(
      (
        await prisma.listing.findMany({
          where: { id: { in: listingIds } },
        })
      ).map((listing) => [listing.id, listing])
    );

    for (const item of items) {
      if (!item.listingId) {
        return res.status(400).json({ error: "Each item must have a listingId" });
      }

      const listing = listingsById.get(item.listingId);

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

      if (!kitchenChecked.has(listing.sellerId)) {
        try {
          await assertSellerKitchenOpen(prisma, listing.sellerId);
          const { assertSellerCanReceiveOrders } = require("../lib/fssaiCompliance");
          await assertSellerCanReceiveOrders(listing.sellerId);
        } catch (err) {
          return res.status(err.statusCode || 400).json({
            error: err.message,
            code: err.code,
          });
        }
        kitchenChecked.add(listing.sellerId);
      }

      let listingAccess = listingAccessCache.get(item.listingId);
      if (!listingAccess) {
        try {
          listingAccess = await authorizeListingForBuyer({
            buyer: req.user,
            listing,
            clientRadiusKm: req.body.nearbyRadiusKm,
            clientDistanceKm: req.body.distanceKm,
          });
          listingAccessCache.set(item.listingId, listingAccess);
        } catch (err) {
          return res.status(err.statusCode || 400).json({
            error: err.message,
            code: err.code,
          });
        }
      }

      if (orderType === "regular" && listing.campaignId) {
        return res.status(400).json({
          error: "Cannot mix regular listings and pre-order products in one order",
        });
      }
      if (orderType === "regular" && listing.catalogType === "PREORDER") {
        return res.status(400).json({
          error: "This item is available through pre-orders only.",
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
        try {
          await assertMadeToOrderCapacity(prisma, current);
        } catch (err) {
          return res.status(err.statusCode || 400).json({
            error: err.message,
            code: err.code,
          });
        }
      }

      if (orderType === "regular" && !isMadeToOrderListing(current)) {
        const usesSchedule =
          isRecurringReadyNowListing(current) || isSameDayHoursListing(current);
        if (current.status === "expired") {
          return res.status(400).json({
            error: `"${current.name}" has expired and cannot be ordered`,
          });
        }
        if (
          !usesSchedule &&
          current.availableAt &&
          new Date(current.availableAt) < new Date()
        ) {
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

      if (orderType === "regular") {
        try {
          await assertRecurringOrderable(prisma, current, quantity);
        } catch (err) {
          return res.status(err.statusCode || 400).json({
            error: err.message,
            code: err.code,
          });
        }
      }

      const enforceStock =
        (orderType === "regular" || current.inventoryMode === "limited") &&
        !isMadeToOrderListing(current) &&
        !isRecurringReadyNowListing(current);
      if (enforceStock && quantity > current.quantity) {
        return res.status(409).json({
          error:
            current.quantity === 0
              ? `"${current.name}" is sold out`
              : `Only ${current.quantity} portions are available for "${current.name}".`,
          availableQuantity: current.quantity,
        });
      }

      preparedItems.push({
        listing: current,
        quantity,
        crossSociety: listingAccess.crossSociety,
        seller: listingAccess.seller || null,
        displayReach: listingAccess.displayReach || null,
      });
    }

    const sellerIds = new Set(preparedItems.map(({ listing }) => listing.sellerId));
    if (sellerIds.size > 1) {
      return res.status(400).json({
        error: "All items in an order must be from the same seller",
      });
    }

    if (orderType === "regular") {
      try {
        const regularListings = preparedItems.map(({ listing }) => listing);
        assertRegularOrderAvailabilityMix(regularListings);
        assertSingleMadeToOrderListingInOrder(regularListings);
      } catch (err) {
        return res.status(err.statusCode || 400).json({
          error: err.message,
          code: err.code,
        });
      }
    }

    const sellerForPayment =
      preparedItems.find((item) => item.seller)?.seller ||
      (await prisma.user.findUnique({
        where: { id: preparedItems[0].listing.sellerId },
        select: {
          paymentPreference: true,
          fulfilmentMode: true,
          deliveryCharge: true,
          deliveryChargeInSociety: true,
          deliveryChargeNearby: true,
          deliveryChargeExtended: true,
        },
      }));
    const isCrossSocietyOrder = preparedItems.some((item) => item.crossSociety);
    try {
      assertPaymentMethodAllowed({
        preference: sellerForPayment && sellerForPayment.paymentPreference,
        paymentMethod,
        sameSociety: !isCrossSocietyOrder,
      });
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }

    let campaign = null;
    let fulfilmentMethod = null;
    let deliveryCharge = 0;
    let fulfilmentAt = null;
    const fulfilmentNotes =
      typeof req.body.fulfilmentNotes === "string"
        ? req.body.fulfilmentNotes.trim() || null
        : null;
    void req.body.deliveryCharge;
    void req.body.nearbyRadiusKm;

    let requestedReadyAt = null;
    try {
      requestedReadyAt = parseRequestedReadyAt(req.body.requestedReadyAt, {
        listings: preparedItems.map(({ listing }) => listing),
        orderType,
      });
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }

    const isCrossSocietyRegular =
      orderType === "regular" && preparedItems.some((item) => item.crossSociety);

    if (
      orderType === "regular" &&
      (isCrossSocietyRegular || offersSellerDelivery(sellerForPayment && sellerForPayment.fulfilmentMode))
    ) {
      try {
        const seller =
          preparedItems.find((item) => item.seller)?.seller ||
          sellerForPayment ||
          (await prisma.user.findUnique({
            where: { id: preparedItems[0].listing.sellerId },
          }));
        const reachBand =
          preparedItems.find((item) => item.displayReach)?.displayReach ||
          (isCrossSocietyRegular ? DELIVERY_REACH.NEARBY : DELIVERY_REACH.IN_SOCIETY);
        const snapshot = snapshotRegularFulfilment({
          seller,
          requestedMethod: req.body.fulfilmentMethod,
          reachBand,
          requireMethod: isCrossSocietyRegular,
        });
        fulfilmentMethod = snapshot.fulfilmentMethod;
        deliveryCharge = snapshot.deliveryCharge;
      } catch (err) {
        return res.status(err.statusCode || 400).json({
          error: err.message,
          code: err.code,
        });
      }
    }

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

    const autoAccepted = skipsSellerAcceptance({
      orderType,
      listings: preparedItems.map(({ listing }) => listing),
    });

    const subtotal = preparedItems.reduce(
      (sum, { listing, quantity }) => sum + listing.price * quantity,
      0
    );
    const platformFee = await getPlatformFee();
    const preCouponTotal = subtotal + platformFee + deliveryCharge;
    const couponCode =
      typeof req.body.couponCode === "string" ? req.body.couponCode.trim() : "";
    if (couponCode && orderType !== "regular") {
      return res.status(400).json({
        error: "Coupons are only available on regular orders right now",
      });
    }

    let order;
    let idempotentReplay = false;
    try {
      const idempotentResult = await runWithOrderIdempotency(prisma, {
        buyerId: req.user.id,
        idempotencyKey,
        orderInclude: orderIncludeForCreate,
        createOrderInTransaction: async (tx) => {
        for (const { listing, quantity } of preparedItems) {
          const reserveStock =
            (orderType === "regular" || listing.inventoryMode === "limited") &&
            !isMadeToOrderListing(listing) &&
            !isRecurringReadyNowListing(listing);
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

        const created = await tx.order.create({
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
            requestedReadyAt,
            status: autoAccepted ? "accepted" : "pending",
            acceptedAt: autoAccepted ? new Date() : null,
            paymentMethod,
            subtotal,
            communityFee: platformFee,
            total: preCouponTotal,
            items: {
              create: preparedItems.map(({ listing, quantity }) => ({
                listingId: listing.id,
                quantity,
                unitPrice: listing.price,
              })),
            },
          },
          include: orderIncludeForCreate,
        });

        if (!couponCode) return created;

        const couponResult = await attachCouponRedemption({
          code: couponCode,
          userId: req.user.id,
          orderSubtotal: subtotal,
          orderId: created.id,
          db: tx,
          status: "REDEEMED",
        });
        if (!couponResult.valid) {
          const err = new Error(couponErrorMessage(couponResult.reason, couponResult));
          err.statusCode = 400;
          err.couponReason = couponResult.reason;
          throw err;
        }

        const discountedTotal = couponMoney(
          Math.max(0, preCouponTotal - couponResult.discountAmount)
        );
        return tx.order.update({
          where: { id: created.id },
          data: { total: discountedTotal },
          include: orderIncludeForCreate,
        });
        },
      });
      order = idempotentResult.order;
      idempotentReplay = idempotentResult.replay;
    } catch (err) {
      if (err.statusCode === 409) {
        return res.status(409).json({
          error: err.message,
          availableQuantity: err.availableQuantity,
        });
      }
      if (err.statusCode === 400 && err.couponReason) {
        return res.status(400).json({
          error: err.message,
          code: err.couponReason,
        });
      }
      throw err;
    }

    if (!idempotentReplay) {
      logger.info("order", `Created ${order.orderNumber} by ${req.user.phone}`);
      void flushNotification(notifyOrderCreated(order));
    }

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

    if (RETIRED_STATUSES.has(status)) {
      return res.status(400).json({
        error: `${status} cannot be assigned to orders`,
      });
    }

    if (status === "rejected") {
      return res.status(400).json({
        error: "Use POST /orders/:id/reject to reject an order",
      });
    }

    const order = await findOrderForUpdate(req.params.id);

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    const isBuyer = order.buyerId === req.user.id;
    const isSeller = isOrderSeller(order, req.user.id);

    if (!isBuyer && !isSeller) {
      return res.status(403).json({ error: "Not allowed to update this order" });
    }

    if (SELLER_ACTIONS.has(status) && !isSeller) {
      return res.status(403).json({ error: "Only the seller can perform this action" });
    }
    if (BUYER_ACTIONS.has(status) && !isBuyer) {
      return res.status(403).json({ error: "Only the buyer can perform this action" });
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

    if (status === "completed" && order.paymentMethod === "cash") {
      if (order.paymentStatus !== "paid") {
        return res.status(400).json({
          error:
            "Please confirm that payment has been received before completing this order.",
        });
      }
    }

    if (status === "ready" && upiBlocksPreparation(order)) {
      return res.status(400).json({
        error:
          "Confirm UPI payment before marking this order ready. The buyer must use I Have Paid first.",
      });
    }

    if (status === "cancelled") {
      const cancelDenied = buyerCancelDeniedReason(order, {
        autoAccepted: orderSkipsSellerAcceptance(order),
      });
      if (cancelDenied) {
        return res.status(400).json({ error: cancelDenied });
      }
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

    let cancelReasonStored = null;
    if (status === "cancelled" && isBuyer) {
      const { reason, otherText, cancelReason } = req.body || {};
      const matched = parseReasonChoice(reason || cancelReason, BUYER_CANCEL_REASONS);
      if (!matched) {
        return res.status(400).json({
          error: `reason is required and must be one of: ${BUYER_CANCEL_REASONS.join(", ")}`,
        });
      }
      const note = typeof otherText === "string" ? otherText : "";
      if (matched === "Other" && !note.trim()) {
        return res.status(400).json({
          error: "Please add a short note when you choose Other",
        });
      }
      try {
        cancelReasonStored = formatStoredReason(matched, note);
      } catch (err) {
        return res.status(err.statusCode || 400).json({ error: err.message });
      }
    }

    const updateData = {
      status,
      ...(TIMESTAMP_FIELDS[status] && { [TIMESTAMP_FIELDS[status]]: new Date() }),
    };

    let updated;

    // The order graph was already loaded for the permission checks. Writing the
    // changed fields onto it avoids a second identical query before we answer.
    if (status === "cancelled") {
      const written = {
        ...updateData,
        paymentStatus: "failed",
        ...(cancelReasonStored ? { cancelReason: cancelReasonStored } : {}),
      };
      await prisma.$transaction(async (tx) => {
        await updateOrderIfCurrentStatus(tx, {
          id: order.id,
          fromStatus: order.status,
          data: written,
          reload: false,
        });

        await restoreReservedInventory(tx, order.items);
        await reverseCouponForOrder(order.id, tx);

        logger.info("order", `Cancelled ${order.orderNumber} — inventory restored`);
      });
      updated = { ...order, ...written };
    } else {
      await updateOrderIfCurrentStatus(prisma, {
        id: order.id,
        fromStatus: order.status,
        data: updateData,
        reload: false,
      });
      updated = { ...order, ...updateData };

      logger.info("order", `${order.orderNumber} → ${status}`);
    }

    res.json(serializeOrderStatusPatch(updated));

    void flushNotification(notifyStatusChange(updated, status));
  })
);

router.post(
  "/:id/reject",
  requireUser,
  asyncHandler(async (req, res) => {
    const { reason, otherText, rejectReason } = req.body || {};
    const rawReason = String(reason || rejectReason || "").trim();
    const matchedReason = REJECT_REASONS.includes(rawReason)
      ? rawReason
      : REJECT_REASONS.find((item) => rawReason.startsWith(item)) || "";

    if (!matchedReason) {
      return res.status(400).json({
        error: `reason is required and must be one of: ${REJECT_REASONS.join(", ")}`,
      });
    }

    const note = typeof otherText === "string" ? otherText.trim() : "";
    if (note.length > 200) {
      return res.status(400).json({ error: "otherText must be at most 200 characters" });
    }
    const storedReason = note ? `${matchedReason}\n${note}` : matchedReason;

    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: orderInclude,
    });

    if (!order) {
      return res.status(404).json({ error: "Order not found" });
    }

    if (!sellerCanDecline(order)) {
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
      const result = await updateOrderIfCurrentStatus(tx, {
        id: order.id,
        fromStatus: order.status,
        data: {
          status: "rejected",
          rejectReason: storedReason,
          rejectedAt: new Date(),
          rejectedBy: req.user.id,
          paymentStatus:
            order.paymentStatus === "seller_confirmed" ||
            order.paymentStatus === "paid"
              ? order.paymentStatus
              : "failed",
        },
      });

      await restoreReservedInventory(tx, order.items);

      logger.info(
        "order",
        `Rejected ${order.orderNumber} by ${req.user.phone}${
          storedReason ? ` — ${storedReason}` : ""
        }`
      );
      return result;
    });

    res.json(serializeOrder(updated));

    await flushNotification(notifyOrderRejected(updated));
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

    if (upiBlocksPreparation(order)) {
      return res.status(400).json({
        error:
          "Ready by can be set after UPI payment is confirmed. Use Confirm Order & Choose Time.",
      });
    }

    const { expectedReadyAt, readyInMinutes } = req.body;

    // Explicit null / missing key with null clears the estimate.
    if (expectedReadyAt === null && readyInMinutes === undefined) {
      const updated = await prisma.order.update({
        where: { id: order.id },
        data: { expectedReadyAt: null },
        include: orderInclude,
      });
      logger.info("order", `Cleared Ready by for ${order.orderNumber}`);
      res.json(serializeOrder(updated));
      return flushNotification(notifyReadyBy(updated, true));
    }

    if (expectedReadyAt !== undefined && readyInMinutes !== undefined) {
      return res.status(400).json({
        error: "Provide either readyInMinutes or expectedReadyAt, not both",
      });
    }

    let readyAt;

    if (readyInMinutes !== undefined) {
      if (
        typeof readyInMinutes !== "number" ||
        !Number.isFinite(readyInMinutes) ||
        readyInMinutes <= 0 ||
        readyInMinutes > 60
      ) {
        return res.status(400).json({
          error: "readyInMinutes must be a positive number no greater than 60",
        });
      }
      readyAt = new Date(Date.now() + readyInMinutes * 60 * 1000);
    } else {
      if (typeof expectedReadyAt !== "string") {
        return res.status(400).json({
          error:
            "expectedReadyAt is required (timezone-aware ISO datetime or null to clear)",
        });
      }

      const timezoneAwareIso = /(?:Z|[+-]\d{2}:\d{2})$/i;
      if (!timezoneAwareIso.test(expectedReadyAt)) {
        return res.status(400).json({
          error: "expectedReadyAt must include a UTC or timezone offset",
        });
      }

      readyAt = new Date(expectedReadyAt);
      if (Number.isNaN(readyAt.getTime())) {
        return res.status(400).json({
          error: "expectedReadyAt must be a valid timezone-aware ISO datetime",
        });
      }
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
    res.json(serializeOrder(updated));
    await flushNotification(notifyReadyBy(updated, false));
  })
);

module.exports = router;
