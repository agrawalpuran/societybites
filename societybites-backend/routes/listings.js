const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { serializeListing } = require("../utils/listingSerializer");

const router = express.Router();

const listingInclude = {
  seller: {
    include: { flat: true },
  },
  reviews: {
    select: { rating: true },
  },
};

router.get(
  "/",
  asyncHandler(async (req, res) => {
    const { societyId, sellerId, status = "active", search, category } = req.query;

    if (!societyId) {
      return res.status(400).json({ error: "societyId query param is required" });
    }

    const searchTerm = search ? String(search).trim() : "";

    let statusFilter;
    if (status === "all") {
      // Seller management view: exclude soft-deleted (inactive) only
      statusFilter = { status: { in: ["active", "paused", "sold_out"] } };
    } else if (status) {
      statusFilter = { status: String(status) };
    } else {
      statusFilter = { status: "active" };
    }

    const listings = await prisma.listing.findMany({
      where: {
        societyId: String(societyId),
        ...(sellerId && { sellerId: String(sellerId) }),
        ...statusFilter,
        ...(category && { category: String(category) }),
        ...(searchTerm && {
          OR: [
            { name: { contains: searchTerm, mode: "insensitive" } },
            { description: { contains: searchTerm, mode: "insensitive" } },
          ],
        }),
      },
      include: listingInclude,
      orderBy: { createdAt: "desc" },
    });

    res.json(listings.map((listing) => serializeListing(listing)));
  })
);

router.get(
  "/:id",
  asyncHandler(async (req, res) => {
    const listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
      include: listingInclude,
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    res.json(serializeListing(listing));
  })
);

router.post(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const {
      name,
      description,
      price,
      quantity = 1,
      availableAt,
      pickupLocation,
      imageUrl,
      weightUnit,
      weightValue,
      tags,
      category,
    } = req.body;

    if (!req.user.societyId) {
      return res.status(400).json({
        error: "You must join a society before creating listings",
      });
    }

    const role = req.user.role || "buyer";
    if (!["seller", "super_admin"].includes(role)) {
      return res.status(403).json({
        error: "Enable selling in Profile before creating listings",
        code: "SELLER_REQUIRED",
      });
    }

    if (!req.user.upiId || !String(req.user.upiId).trim()) {
      return res.status(400).json({
        error: "Add a UPI ID in Profile before creating listings",
        code: "UPI_REQUIRED",
      });
    }

    if (!name || price === undefined) {
      return res.status(400).json({
        error: "name and price are required",
      });
    }

    const listing = await prisma.listing.create({
      data: {
        sellerId: req.user.id,
        societyId: req.user.societyId,
        name,
        description,
        price: parseFloat(price),
        quantity: parseInt(quantity, 10),
        availableAt: availableAt ? new Date(availableAt) : null,
        pickupLocation: pickupLocation || "My Home (Verified)",
        imageUrl,
        weightUnit: weightUnit || null,
        weightValue: weightValue || null,
        tags: Array.isArray(tags) ? tags : [],
        category: category || null,
      },
      include: listingInclude,
    });

    res.status(201).json(serializeListing(listing));
  })
);

router.patch(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    const listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to update this listing" });
    }

    const {
      name,
      description,
      price,
      quantity,
      availableAt,
      pickupLocation,
      imageUrl,
      status,
      weightUnit,
      weightValue,
      tags,
      category,
    } = req.body;

    const data = {
      ...(name !== undefined && { name }),
      ...(description !== undefined && { description }),
      ...(price !== undefined && { price: parseFloat(price) }),
      ...(quantity !== undefined && { quantity: parseInt(quantity, 10) }),
      ...(availableAt !== undefined && {
        availableAt: availableAt ? new Date(availableAt) : null,
      }),
      ...(pickupLocation !== undefined && { pickupLocation }),
      ...(imageUrl !== undefined && { imageUrl }),
      ...(weightUnit !== undefined && { weightUnit: weightUnit || null }),
      ...(weightValue !== undefined && { weightValue: weightValue || null }),
      ...(tags !== undefined && { tags: Array.isArray(tags) ? tags : [] }),
      ...(category !== undefined && { category: category || null }),
      ...(status !== undefined && { status }),
    };

    if (quantity !== undefined && parseInt(quantity, 10) > 0 && listing.status === "sold_out") {
      data.status = "active";
    }

    const updated = await prisma.listing.update({
      where: { id: req.params.id },
      data,
      include: listingInclude,
    });

    res.json(serializeListing(updated));
  })
);

router.patch(
  "/:id/pause",
  requireUser,
  asyncHandler(async (req, res) => {
    const listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to pause this listing" });
    }

    if (listing.status === "paused") {
      return res.status(400).json({ error: "Listing is already paused" });
    }

    if (listing.status === "inactive") {
      return res.status(400).json({ error: "Cannot pause a removed listing" });
    }

    if (listing.status !== "active" && listing.status !== "sold_out") {
      return res.status(400).json({
        error: `Cannot pause a listing with status "${listing.status}"`,
      });
    }

    const updated = await prisma.listing.update({
      where: { id: listing.id },
      data: { status: "paused" },
      include: listingInclude,
    });

    res.json(serializeListing(updated));
  })
);

router.patch(
  "/:id/resume",
  requireUser,
  asyncHandler(async (req, res) => {
    const listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to resume this listing" });
    }

    if (listing.status === "active") {
      return res.status(400).json({ error: "Listing is already active" });
    }

    if (listing.status !== "paused") {
      return res.status(400).json({
        error: `Cannot resume a listing with status "${listing.status}"`,
      });
    }

    const updated = await prisma.listing.update({
      where: { id: listing.id },
      data: { status: "active" },
      include: listingInclude,
    });

    res.json(serializeListing(updated));
  })
);

router.delete(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    const listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to delete this listing" });
    }

    await prisma.listing.update({
      where: { id: req.params.id },
      data: { status: "inactive" },
    });

    res.json({ success: true });
  })
);

module.exports = router;
