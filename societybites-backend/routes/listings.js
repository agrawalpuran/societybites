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

    const listings = await prisma.listing.findMany({
      where: {
        societyId: String(societyId),
        ...(sellerId && { sellerId: String(sellerId) }),
        ...(status && { status: String(status) }),
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
