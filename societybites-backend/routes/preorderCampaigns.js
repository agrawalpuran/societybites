const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { serializeListing } = require("../utils/listingSerializer");
const { serializeOrder } = require("../utils/listingSerializer");
const {
  CAMPAIGN_STATUSES,
  parseDate,
  assertCampaignTimeline,
  normalizeFulfilmentMethods,
  normalizeInventoryMode,
  lazyCloseCampaign,
  campaignHasOrders,
  serializeCampaign,
  requireSeller,
  requireCampaignOwner,
  buildCampaignSummary,
} = require("../lib/preorder");

const router = express.Router();

const campaignInclude = {
  products: {
    include: {
      seller: { include: { flat: true } },
      reviews: { select: { rating: true } },
    },
    orderBy: { createdAt: "asc" },
  },
};

function serializeCampaignWithProducts(campaign) {
  const base = serializeCampaign(campaign);
  base.products = (campaign.products || []).map(serializeListing);
  return base;
}

function buildProductData(user, campaign, product) {
  if (!product || !product.name || product.price === undefined) {
    const err = new Error("Each product needs name and price");
    err.statusCode = 400;
    throw err;
  }
  const inventoryMode = normalizeInventoryMode(product.inventoryMode);
  let quantity = 0;
  if (inventoryMode === "limited") {
    quantity = parseInt(product.quantity ?? product.maxQuantity, 10);
    if (!quantity || quantity < 1) {
      const err = new Error(`Limited product "${product.name}" needs quantity >= 1`);
      err.statusCode = 400;
      throw err;
    }
  }
  return {
    sellerId: user.id,
    societyId: user.societyId,
    campaignId: campaign.id,
    name: product.name,
    description: product.description || null,
    price: parseFloat(product.price),
    quantity,
    inventoryMode,
    imageUrl: product.imageUrl || null,
    weightUnit: product.weightUnit || null,
    weightValue: product.weightValue || null,
    tags: Array.isArray(product.tags) ? product.tags : [],
    category: product.category || null,
    pickupLocation: product.pickupLocation || "My Home (Verified)",
    status: "active",
  };
}

router.get(
  "/",
  asyncHandler(async (req, res) => {
    const { societyId, sellerId, status } = req.query;
    if (!societyId) {
      return res.status(400).json({ error: "societyId query param is required" });
    }

    const now = new Date();
    const openDue = await prisma.preOrderCampaign.findMany({
      where: {
        societyId: String(societyId),
        status: "open",
        orderCutoffAt: { lte: now },
      },
      select: { id: true },
    });
    if (openDue.length > 0) {
      await prisma.preOrderCampaign.updateMany({
        where: { id: { in: openDue.map((c) => c.id) } },
        data: { status: "closed" },
      });
    }

    const campaigns = await prisma.preOrderCampaign.findMany({
      where: {
        societyId: String(societyId),
        ...(sellerId && { sellerId: String(sellerId) }),
        ...(status && { status: String(status) }),
      },
      include: campaignInclude,
      orderBy: { fulfilmentAt: "asc" },
    });

    res.json(campaigns.map(serializeCampaignWithProducts));
  })
);

router.get(
  "/:id",
  asyncHandler(async (req, res) => {
    let campaign = await prisma.preOrderCampaign.findUnique({
      where: { id: req.params.id },
      include: campaignInclude,
    });
    if (!campaign) {
      return res.status(404).json({ error: "Pre-order campaign not found" });
    }
    const previousStatus = campaign.status;
    campaign = await lazyCloseCampaign(campaign);
    if (campaign.status !== previousStatus || !campaign.products) {
      campaign = await prisma.preOrderCampaign.findUnique({
        where: { id: req.params.id },
        include: campaignInclude,
      });
    }
    res.json(serializeCampaignWithProducts(campaign));
  })
);

router.get(
  "/:id/summary",
  requireUser,
  asyncHandler(async (req, res) => {
    requireSeller(req.user);
    let campaign = await prisma.preOrderCampaign.findUnique({
      where: { id: req.params.id },
    });
    if (!campaign) {
      return res.status(404).json({ error: "Pre-order campaign not found" });
    }
    requireCampaignOwner(req.user, campaign);
    campaign = await lazyCloseCampaign(campaign);
    const summary = await buildCampaignSummary(campaign);
    res.json(summary);
  })
);

router.get(
  "/:id/orders",
  requireUser,
  asyncHandler(async (req, res) => {
    requireSeller(req.user);
    const campaign = await prisma.preOrderCampaign.findUnique({
      where: { id: req.params.id },
    });
    if (!campaign) {
      return res.status(404).json({ error: "Pre-order campaign not found" });
    }
    requireCampaignOwner(req.user, campaign);

    const { status } = req.query;
    const orders = await prisma.order.findMany({
      where: {
        campaignId: campaign.id,
        type: "pre_order",
        ...(status ? { status: String(status) } : {}),
      },
      include: {
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
      },
      orderBy: { createdAt: "desc" },
    });

    res.json(orders.map(serializeOrder));
  })
);

router.post(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    requireSeller(req.user);

    const title = typeof req.body?.title === "string" ? req.body.title.trim() : "";
    if (!title) {
      return res.status(400).json({ error: "title is required" });
    }

    const orderOpenAt = parseDate(req.body.orderOpenAt, "orderOpenAt");
    const orderCutoffAt = parseDate(req.body.orderCutoffAt, "orderCutoffAt");
    const fulfilmentAt = parseDate(req.body.fulfilmentAt, "fulfilmentAt");
    assertCampaignTimeline(orderOpenAt, orderCutoffAt, fulfilmentAt);

    const status = req.body.status ? String(req.body.status) : "draft";
    if (!CAMPAIGN_STATUSES.includes(status) || status === "closed") {
      return res.status(400).json({ error: "status must be draft, open, or cancelled" });
    }

    const offeredFulfilmentMethods = normalizeFulfilmentMethods(
      req.body.offeredFulfilmentMethods
    );
    const defaultDeliveryCharge = Number(req.body.defaultDeliveryCharge || 0);
    if (Number.isNaN(defaultDeliveryCharge) || defaultDeliveryCharge < 0) {
      return res.status(400).json({ error: "defaultDeliveryCharge must be >= 0" });
    }

    const products = Array.isArray(req.body.products) ? req.body.products : [];

    const campaign = await prisma.$transaction(async (tx) => {
      const created = await tx.preOrderCampaign.create({
        data: {
          sellerId: req.user.id,
          societyId: req.user.societyId,
          title,
          description: req.body.description || null,
          coverImageUrl:
            typeof req.body.coverImageUrl === "string"
              ? req.body.coverImageUrl.trim() || null
              : null,
          fulfilmentNotes:
            typeof req.body.fulfilmentNotes === "string"
              ? req.body.fulfilmentNotes.trim() || null
              : null,
          orderOpenAt,
          orderCutoffAt,
          fulfilmentAt,
          status,
          offeredFulfilmentMethods,
          defaultDeliveryCharge,
        },
      });

      for (const product of products) {
        await tx.listing.create({
          data: buildProductData(req.user, created, product),
        });
      }

      return tx.preOrderCampaign.findUnique({
        where: { id: created.id },
        include: campaignInclude,
      });
    });

    res.status(201).json(serializeCampaignWithProducts(campaign));
  })
);

router.patch(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    requireSeller(req.user);

    const existing = await prisma.preOrderCampaign.findUnique({
      where: { id: req.params.id },
      include: { products: true },
    });
    if (!existing) {
      return res.status(404).json({ error: "Pre-order campaign not found" });
    }
    if (existing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to update this campaign" });
    }

    const hasOrders = await campaignHasOrders(existing.id);
    if (hasOrders) {
      const protectedFields = [
        "title",
        "orderOpenAt",
        "orderCutoffAt",
        "fulfilmentAt",
        "offeredFulfilmentMethods",
        "defaultDeliveryCharge",
        "products",
      ];
      if (protectedFields.some((field) => req.body[field] !== undefined)) {
        return res.status(400).json({
          error: "Campaign settings cannot be changed after orders have been placed.",
        });
      }
      if (
        req.body.status !== undefined &&
        req.body.status !== existing.status &&
        !(existing.status === "open" && req.body.status === "closed")
      ) {
        return res.status(400).json({
          error: "Only closing orders is allowed after orders have been placed.",
        });
      }
    }

    const data = {};
    if (req.body.title !== undefined) {
      const title = String(req.body.title).trim();
      if (!title) return res.status(400).json({ error: "title cannot be empty" });
      data.title = title;
    }
    if (req.body.description !== undefined) {
      data.description = req.body.description || null;
    }
    if (req.body.coverImageUrl !== undefined) {
      data.coverImageUrl =
        typeof req.body.coverImageUrl === "string"
          ? req.body.coverImageUrl.trim() || null
          : null;
    }
    if (req.body.fulfilmentNotes !== undefined) {
      data.fulfilmentNotes =
        typeof req.body.fulfilmentNotes === "string"
          ? req.body.fulfilmentNotes.trim() || null
          : null;
    }
    if (req.body.status !== undefined) {
      if (!CAMPAIGN_STATUSES.includes(req.body.status)) {
        return res.status(400).json({ error: "Invalid campaign status" });
      }
      data.status = req.body.status;
    }
    if (req.body.offeredFulfilmentMethods !== undefined) {
      data.offeredFulfilmentMethods = normalizeFulfilmentMethods(
        req.body.offeredFulfilmentMethods
      );
    }
    if (req.body.defaultDeliveryCharge !== undefined) {
      const charge = Number(req.body.defaultDeliveryCharge);
      if (Number.isNaN(charge) || charge < 0) {
        return res.status(400).json({ error: "defaultDeliveryCharge must be >= 0" });
      }
      data.defaultDeliveryCharge = charge;
    }

    const orderOpenAt = req.body.orderOpenAt !== undefined
      ? parseDate(req.body.orderOpenAt, "orderOpenAt")
      : existing.orderOpenAt;
    const orderCutoffAt = req.body.orderCutoffAt !== undefined
      ? parseDate(req.body.orderCutoffAt, "orderCutoffAt")
      : existing.orderCutoffAt;
    const fulfilmentAt = req.body.fulfilmentAt !== undefined
      ? parseDate(req.body.fulfilmentAt, "fulfilmentAt")
      : existing.fulfilmentAt;
    assertCampaignTimeline(orderOpenAt, orderCutoffAt, fulfilmentAt);
    if (req.body.orderOpenAt !== undefined) data.orderOpenAt = orderOpenAt;
    if (req.body.orderCutoffAt !== undefined) data.orderCutoffAt = orderCutoffAt;
    if (req.body.fulfilmentAt !== undefined) data.fulfilmentAt = fulfilmentAt;

    if (Array.isArray(req.body.products)) {
      if (hasOrders) {
        return res.status(400).json({
          error: "Cannot replace campaign products after orders have been placed",
        });
      }
    }

    const campaign = await prisma.$transaction(async (tx) => {
      await tx.preOrderCampaign.update({
        where: { id: existing.id },
        data,
      });

      if (Array.isArray(req.body.products) && !hasOrders) {
        await tx.listing.deleteMany({ where: { campaignId: existing.id } });
        for (const product of req.body.products) {
          await tx.listing.create({
            data: buildProductData(req.user, existing, product),
          });
        }
      }

      return tx.preOrderCampaign.findUnique({
        where: { id: existing.id },
        include: campaignInclude,
      });
    });

    res.json(serializeCampaignWithProducts(campaign));
  })
);

router.post(
  "/:id/products",
  requireUser,
  asyncHandler(async (req, res) => {
    requireSeller(req.user);
    const campaign = await prisma.preOrderCampaign.findUnique({
      where: { id: req.params.id },
    });
    if (!campaign) {
      return res.status(404).json({ error: "Pre-order campaign not found" });
    }
    if (campaign.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to update this campaign" });
    }
    if (campaign.status === "cancelled") {
      return res.status(400).json({ error: "Cannot add products to a cancelled campaign" });
    }

    const listing = await prisma.listing.create({
      data: buildProductData(req.user, campaign, req.body),
      include: {
        seller: { include: { flat: true } },
        reviews: { select: { rating: true } },
      },
    });

    res.status(201).json(serializeListing(listing));
  })
);

router.patch(
  "/:id/products/:productId",
  requireUser,
  asyncHandler(async (req, res) => {
    requireSeller(req.user);
    const campaign = await prisma.preOrderCampaign.findUnique({
      where: { id: req.params.id },
    });
    if (!campaign) {
      return res.status(404).json({ error: "Pre-order campaign not found" });
    }
    if (campaign.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to update this campaign" });
    }

    const listing = await prisma.listing.findUnique({
      where: { id: req.params.productId },
    });
    if (!listing || listing.campaignId !== campaign.id) {
      return res.status(404).json({ error: "Campaign product not found" });
    }

    if (await campaignHasOrders(campaign.id)) {
      return res.status(400).json({
        error: "This product cannot be changed because orders have already been placed.",
      });
    }

    const data = {};
    if (req.body.name !== undefined) {
      const name = String(req.body.name).trim();
      if (!name) {
        return res.status(400).json({ error: "Product name cannot be empty" });
      }
      data.name = name;
    }
    if (req.body.description !== undefined) data.description = req.body.description;
    if (req.body.price !== undefined) {
      const price = Number(req.body.price);
      if (!Number.isFinite(price) || price < 0) {
        return res.status(400).json({ error: "Product price must be >= 0" });
      }
      data.price = price;
    }
    if (req.body.imageUrl !== undefined) data.imageUrl = req.body.imageUrl;
    if (req.body.status !== undefined) data.status = req.body.status;
    if (req.body.inventoryMode !== undefined) {
      data.inventoryMode = normalizeInventoryMode(req.body.inventoryMode);
    }
    const mode = data.inventoryMode || listing.inventoryMode || "demand";
    if (req.body.quantity !== undefined || req.body.maxQuantity !== undefined) {
      if (mode === "limited") {
        const quantity = parseInt(req.body.quantity ?? req.body.maxQuantity, 10);
        if (!quantity || quantity < 1) {
          return res.status(400).json({ error: "Limited products need quantity >= 1" });
        }
        data.quantity = quantity;
      } else {
        data.quantity = 0;
      }
    } else if (data.inventoryMode === "demand") {
      data.quantity = 0;
    } else if (data.inventoryMode === "limited" && listing.quantity < 1) {
      return res.status(400).json({
        error: "Limited products need quantity >= 1",
      });
    }

    const updated = await prisma.listing.update({
      where: { id: listing.id },
      data,
      include: {
        seller: { include: { flat: true } },
        reviews: { select: { rating: true } },
      },
    });

    res.json(serializeListing(updated));
  })
);

router.delete(
  "/:id/products/:productId",
  requireUser,
  asyncHandler(async (req, res) => {
    requireSeller(req.user);
    const campaign = await prisma.preOrderCampaign.findUnique({
      where: { id: req.params.id },
    });
    if (!campaign) {
      return res.status(404).json({ error: "Pre-order campaign not found" });
    }
    if (campaign.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to update this campaign" });
    }

    const listing = await prisma.listing.findUnique({
      where: { id: req.params.productId },
    });
    if (!listing || listing.campaignId !== campaign.id) {
      return res.status(404).json({ error: "Campaign product not found" });
    }
    if (await campaignHasOrders(campaign.id)) {
      return res.status(400).json({
        error: "This product cannot be removed because orders have already been placed.",
      });
    }

    await prisma.listing.delete({ where: { id: listing.id } });
    res.status(204).send();
  })
);

module.exports = router;
