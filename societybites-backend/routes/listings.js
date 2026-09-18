const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser, requireJoinedSociety } = require("../middleware/requireUser");
const { serializeListing } = require("../utils/listingSerializer");
const {
  parseFoodType,
  assertFoodTypeTagCompatibility,
} = require("../utils/foodType");
const {
  expireDueListings,
  expireListingIfDue,
} = require("../utils/listingExpiry");
const { campaignHasOrders } = require("../lib/preorder");
const {
  discoverNearbySellers,
  getNearbySellerStorefront,
} = require("../lib/nearbyDiscovery");
const {
  discoverGuestKitchens,
  getGuestKitchenStorefront,
} = require("../lib/guestDiscovery");
const {
  parseListingCategories,
  categoryWriteFields,
  categoryQueryFilter,
} = require("../utils/listingCategories");
const {
  parseCatalogType,
  catalogListWhere,
  isRegularMarketplaceListing,
  listingInActiveCampaign,
  ACTIVE_CAMPAIGN_MOVE_ERROR,
  ACTIVE_CAMPAIGN_DELETE_ERROR,
} = require("../lib/listingCatalog");

const router = express.Router();

const listingInclude = {
  seller: {
    include: { flat: true },
  },
  reviews: {
    select: { rating: true },
  },
};

async function rejectCommittedCampaignProductMutation(listing, res) {
  if (!listing.campaignId || !(await campaignHasOrders(listing.campaignId))) {
    return false;
  }
  res.status(400).json({
    error: "This product cannot be changed because orders have already been placed.",
  });
  return true;
}

router.get(
  "/guest-kitchens",
  asyncHandler(async (req, res) => {
    const payload = await discoverGuestKitchens({ query: req.query });
    res.json(payload);
  })
);

router.get(
  "/guest-kitchens/:sellerId",
  asyncHandler(async (req, res) => {
    const payload = await getGuestKitchenStorefront({
      sellerId: req.params.sellerId,
      query: req.query,
    });
    res.json(payload);
  })
);

router.get(
  "/nearby-sellers",
  requireUser,
  asyncHandler(async (req, res) => {
    const societyId = requireJoinedSociety(req, res);
    if (!societyId) return;

    const payload = await discoverNearbySellers({
      buyer: req.user,
      query: req.query,
    });
    res.json(payload);
  })
);

router.get(
  "/nearby-sellers/:sellerId",
  requireUser,
  asyncHandler(async (req, res) => {
    const societyId = requireJoinedSociety(req, res);
    if (!societyId) return;

    const payload = await getNearbySellerStorefront({
      buyer: req.user,
      sellerId: req.params.sellerId,
      query: req.query,
    });
    res.json(payload);
  })
);

router.get(
  "/",
  requireUser,
  asyncHandler(async (req, res) => {
    const societyId = requireJoinedSociety(req, res);
    if (!societyId) return;

    const { sellerId, status = "active", search, category, catalogType } = req.query;

    const searchTerm = search ? String(search).trim() : "";

    // Lazy expiry before any listing read (no cron).
    await expireDueListings(prisma, {
      societyId,
      ...(sellerId && { sellerId: String(sellerId) }),
    });

    let statusFilter;
    if (status === "all") {
      // Seller management view: exclude soft-deleted (inactive) only
      statusFilter = {
        status: { in: ["active", "paused", "sold_out", "expired"] },
      };
    } else if (status) {
      statusFilter = { status: String(status) };
    } else {
      statusFilter = { status: "active" };
    }

    let catalogWhere;
    try {
      catalogWhere = catalogListWhere({
        catalogType,
        sellerId,
        userId: req.user.id,
      });
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }

    const extraFilters = [];
    const categoryFilter = categoryQueryFilter(category);
    if (Object.keys(categoryFilter).length > 0) extraFilters.push(categoryFilter);
    if (searchTerm) {
      extraFilters.push({
        OR: [
          { name: { contains: searchTerm, mode: "insensitive" } },
          { description: { contains: searchTerm, mode: "insensitive" } },
        ],
      });
    }

    const listings = await prisma.listing.findMany({
      where: {
        societyId,
        ...catalogWhere,
        ...(sellerId && { sellerId: String(sellerId) }),
        ...statusFilter,
        ...(extraFilters.length === 1 ? extraFilters[0] : {}),
        ...(extraFilters.length > 1 ? { AND: extraFilters } : {}),
      },
      include: listingInclude,
      orderBy: { createdAt: "desc" },
    });

    res.json(listings.map((listing) => serializeListing(listing)));
  })
);

router.get(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    const societyId = requireJoinedSociety(req, res);
    if (!societyId) return;

    let listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
      include: listingInclude,
    });

    if (!listing || listing.societyId !== societyId) {
      return res.status(404).json({ error: "Listing not found" });
    }

    const isOwner = listing.sellerId === req.user.id;
    if (!isRegularMarketplaceListing(listing) && !isOwner) {
      return res.status(404).json({ error: "Listing not found" });
    }

    listing = await expireListingIfDue(prisma, listing, { include: listingInclude });

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
      foodType,
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

    const parsedFoodType = parseFoodType(foodType, { required: true });
    const listingTags = Array.isArray(tags) ? tags : [];
    assertFoodTypeTagCompatibility(parsedFoodType, listingTags);

    const availableAtDate = availableAt ? new Date(availableAt) : null;
    if (availableAtDate && availableAtDate < new Date()) {
      return res.status(400).json({
        error: "Available Until must be in the future",
      });
    }

    const parsedCatalogType = parseCatalogType(req.body.catalogType);
    let parsedCategories;
    try {
      parsedCategories = parseListingCategories(req.body, { required: true });
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }

    const listing = await prisma.listing.create({
      data: {
        sellerId: req.user.id,
        societyId: req.user.societyId,
        name,
        description,
        price: parseFloat(price),
        quantity: parseInt(quantity, 10),
        availableAt: availableAtDate,
        pickupLocation: pickupLocation || "My Home (Verified)",
        imageUrl,
        weightUnit: weightUnit || null,
        weightValue: weightValue || null,
        tags: listingTags,
        foodType: parsedFoodType,
        ...categoryWriteFields(parsedCategories),
        catalogType: parsedCatalogType,
      },
      include: listingInclude,
    });

    res.status(201).json(serializeListing(listing));
  })
);

router.patch(
  "/:id/catalog",
  requireUser,
  asyncHandler(async (req, res) => {
    const role = req.user.role || "buyer";
    if (!["seller", "super_admin"].includes(role)) {
      return res.status(403).json({
        error: "Enable selling in Profile before managing listings",
        code: "SELLER_REQUIRED",
      });
    }

    let nextType;
    try {
      nextType = parseCatalogType(req.body && req.body.catalogType, {
        required: true,
      });
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }

    const listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
      include: listingInclude,
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to update this listing" });
    }

    if (await listingInActiveCampaign(prisma, listing)) {
      return res.status(400).json({ error: ACTIVE_CAMPAIGN_MOVE_ERROR });
    }

    if ((listing.catalogType || "REGULAR") === nextType) {
      return res.json(serializeListing(listing));
    }

    const updated = await prisma.listing.update({
      where: { id: listing.id },
      data: { catalogType: nextType },
      include: listingInclude,
    });

    res.json(serializeListing(updated));
  })
);

router.patch(
  "/:id",
  requireUser,
  asyncHandler(async (req, res) => {
    let listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to update this listing" });
    }

    if (await rejectCommittedCampaignProductMutation(listing, res)) return;

    listing = await expireListingIfDue(prisma, listing);

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
      foodType,
    } = req.body;

    const data = {
      ...(name !== undefined && { name }),
      ...(description !== undefined && { description }),
      ...(price !== undefined && { price: parseFloat(price) }),
      ...(quantity !== undefined && { quantity: parseInt(quantity, 10) }),
      ...(pickupLocation !== undefined && { pickupLocation }),
      ...(imageUrl !== undefined && { imageUrl }),
      ...(weightUnit !== undefined && { weightUnit: weightUnit || null }),
      ...(weightValue !== undefined && { weightValue: weightValue || null }),
      ...(tags !== undefined && { tags: Array.isArray(tags) ? tags : [] }),
      ...(status !== undefined && { status }),
    };

    let parsedCategories;
    try {
      parsedCategories = parseListingCategories(req.body, { required: false });
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }
    if (parsedCategories !== undefined) {
      Object.assign(data, categoryWriteFields(parsedCategories));
    }

    if (foodType !== undefined) {
      data.foodType = parseFoodType(foodType, { required: true });
    }

    const tagsForCompat =
      data.tags !== undefined ? data.tags : listing.tags;
    const foodTypeForCompat =
      data.foodType !== undefined ? data.foodType : listing.foodType;
    assertFoodTypeTagCompatibility(foodTypeForCompat, tagsForCompat);

    if (availableAt !== undefined) {
      const availableAtDate = availableAt ? new Date(availableAt) : null;
      data.availableAt = availableAtDate;
      // Renew via edit: future Available Until reactivates expired listings
      if (availableAtDate && availableAtDate > new Date() && listing.status === "expired") {
        data.status = "active";
      }
    }

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
    let listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to pause this listing" });
    }

    if (await rejectCommittedCampaignProductMutation(listing, res)) return;

    listing = await expireListingIfDue(prisma, listing);

    if (listing.status === "paused") {
      return res.status(400).json({ error: "Listing is already paused" });
    }

    if (listing.status === "inactive") {
      return res.status(400).json({ error: "Cannot pause a removed listing" });
    }

    if (listing.status === "expired") {
      return res.status(400).json({
        error: "Cannot pause an expired listing. Renew it first.",
      });
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
    let listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to resume this listing" });
    }

    if (await rejectCommittedCampaignProductMutation(listing, res)) return;

    listing = await expireListingIfDue(prisma, listing);

    if (listing.status === "expired") {
      return res.status(400).json({
        error: "Listing has expired. Renew it with a new Available Until time.",
      });
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

router.patch(
  "/:id/renew",
  requireUser,
  asyncHandler(async (req, res) => {
    let listing = await prisma.listing.findUnique({
      where: { id: req.params.id },
    });

    if (!listing) {
      return res.status(404).json({ error: "Listing not found" });
    }

    if (listing.sellerId !== req.user.id) {
      return res.status(403).json({ error: "Not allowed to renew this listing" });
    }

    if (await rejectCommittedCampaignProductMutation(listing, res)) return;

    listing = await expireListingIfDue(prisma, listing);

    if (listing.status !== "expired") {
      return res.status(400).json({
        error: `Only expired listings can be renewed (current status: "${listing.status}")`,
      });
    }

    const { availableAt } = req.body;
    if (!availableAt) {
      return res.status(400).json({ error: "availableAt is required to renew" });
    }

    const availableAtDate = new Date(availableAt);
    if (Number.isNaN(availableAtDate.getTime())) {
      return res.status(400).json({ error: "availableAt must be a valid date" });
    }
    if (availableAtDate <= new Date()) {
      return res.status(400).json({
        error: "Available Until must be in the future",
      });
    }

    const updated = await prisma.listing.update({
      where: { id: listing.id },
      data: {
        availableAt: availableAtDate,
        status: "active",
      },
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

    if (await listingInActiveCampaign(prisma, listing)) {
      return res.status(400).json({ error: ACTIVE_CAMPAIGN_DELETE_ERROR });
    }

    if (await rejectCommittedCampaignProductMutation(listing, res)) return;

    await prisma.listing.update({
      where: { id: req.params.id },
      data: { status: "inactive" },
    });

    res.json({ success: true });
  })
);

module.exports = router;
