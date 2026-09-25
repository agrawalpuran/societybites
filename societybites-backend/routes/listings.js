const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser, requireJoinedSociety } = require("../middleware/requireUser");
const { serializeListing, attachQuantitySold } = require("../utils/listingSerializer");
const {
  parseFoodType,
  assertFoodTypeTagCompatibility,
} = require("../utils/foodType");
const {
  expireDueListings,
  expireListingIfDue,
  DISCOVERABLE_STATUSES,
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
const {
  availabilityWriteFields,
  availabilityUpdateFields,
  attachMadeToOrderCapacity,
  assertSingleBuyerVisibleMadeToOrder,
  isBuyerVisibleMadeToOrder,
  isMadeToOrderListing,
} = require("../lib/listingAvailability");

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
    } else if (status === "discoverable") {
      // Buyer marketplace: currently orderable plus expired (visible, not orderable)
      statusFilter = { status: { in: DISCOVERABLE_STATUSES } };
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

    const withCapacity = await attachMadeToOrderCapacity(prisma, listings);
    await attachQuantitySold(prisma, withCapacity);
    res.json(withCapacity.map((listing) => serializeListing(listing)));
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
    const [withCapacity] = await attachMadeToOrderCapacity(prisma, [listing]);
    const payload = withCapacity || listing;
    await attachQuantitySold(prisma, [payload]);
    res.json(serializeListing(payload));
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
    let availabilityFields;
    try {
      parsedCategories = parseListingCategories(req.body, { required: true });
      availabilityFields = availabilityWriteFields({
        catalogType: parsedCatalogType,
        availabilityMode: req.body.availabilityMode,
        preparationTimeMinutes: req.body.preparationTimeMinutes,
        maxDailyOrders: req.body.maxDailyOrders,
      });
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }

    try {
      if (isBuyerVisibleMadeToOrder({ ...availabilityFields, status: "active" })) {
        await assertSingleBuyerVisibleMadeToOrder(prisma, {
          sellerId: req.user.id,
        });
      }
    } catch (err) {
      return res.status(err.statusCode || 400).json({
        error: err.message,
        code: err.code,
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
        availableAt: availableAtDate,
        pickupLocation: pickupLocation || "My Home (Verified)",
        imageUrl,
        weightUnit: weightUnit || null,
        weightValue: weightValue || null,
        tags: listingTags,
        foodType: parsedFoodType,
        ...categoryWriteFields(parsedCategories),
        catalogType: parsedCatalogType,
        ...availabilityFields,
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
      data:
        nextType === "PREORDER"
          ? {
              catalogType: nextType,
              availabilityMode: "READY_NOW",
              preparationTimeMinutes: null,
              maxDailyOrders: null,
            }
          : { catalogType: nextType },
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

    try {
      const availabilityFields = availabilityUpdateFields(req.body, listing);
      if (availabilityFields) Object.assign(data, availabilityFields);
    } catch (err) {
      return res.status(err.statusCode || 400).json({ error: err.message });
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

    try {
      if (isBuyerVisibleMadeToOrder({ ...listing, ...data })) {
        await assertSingleBuyerVisibleMadeToOrder(prisma, {
          sellerId: listing.sellerId,
          excludeListingId: listing.id,
        });
      }
    } catch (err) {
      return res.status(err.statusCode || 400).json({
        error: err.message,
        code: err.code,
      });
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
  "/bulk/pause",
  requireUser,
  asyncHandler(async (req, res) => {
    const role = req.user.role || "buyer";
    if (!["seller", "super_admin"].includes(role)) {
      return res.status(403).json({
        error: "Enable selling in Profile before managing listings",
        code: "SELLER_REQUIRED",
      });
    }

    const sellerId = req.user.id;
    await expireDueListings(prisma, { sellerId });

    const candidates = await prisma.listing.findMany({
      where: {
        sellerId,
        campaignId: null,
        status: { in: ["active", "sold_out"] },
      },
      select: { id: true },
    });

    const eligibleIds = [];
    for (const listing of candidates) {
      if (await listingInActiveCampaign(prisma, listing)) continue;
      eligibleIds.push(listing.id);
    }

    if (eligibleIds.length === 0) {
      return res.status(400).json({
        error: "No listings are currently available to pause.",
        pausedCount: 0,
      });
    }

    const result = await prisma.listing.updateMany({
      where: { id: { in: eligibleIds }, sellerId },
      data: { status: "paused" },
    });

    res.json({ pausedCount: result.count });
  })
);

router.patch(
  "/bulk/resume",
  requireUser,
  asyncHandler(async (req, res) => {
    const role = req.user.role || "buyer";
    if (!["seller", "super_admin"].includes(role)) {
      return res.status(403).json({
        error: "Enable selling in Profile before managing listings",
        code: "SELLER_REQUIRED",
      });
    }

    const sellerId = req.user.id;
    await expireDueListings(prisma, { sellerId });

    const candidates = await prisma.listing.findMany({
      where: {
        sellerId,
        campaignId: null,
        status: "paused",
      },
      select: {
        id: true,
        availabilityMode: true,
        catalogType: true,
        campaignId: true,
        status: true,
      },
    });

    const liveMadeToOrder = await prisma.listing.findFirst({
      where: {
        sellerId,
        campaignId: null,
        catalogType: { not: "PREORDER" },
        availabilityMode: "MADE_TO_ORDER",
        status: { in: ["active", "sold_out"] },
      },
      select: { id: true },
    });
    let reservedMadeToOrder = Boolean(liveMadeToOrder);

    const eligibleIds = [];
    for (const listing of candidates) {
      if (await listingInActiveCampaign(prisma, listing)) continue;
      if (isMadeToOrderListing(listing)) {
        if (reservedMadeToOrder) continue;
        reservedMadeToOrder = true;
      }
      eligibleIds.push(listing.id);
    }

    if (eligibleIds.length === 0) {
      return res.status(400).json({
        error: "No paused listings are eligible to renew.",
        resumedCount: 0,
      });
    }

    const result = await prisma.listing.updateMany({
      where: { id: { in: eligibleIds }, sellerId },
      data: { status: "active" },
    });

    res.json({ resumedCount: result.count });
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

    try {
      if (isBuyerVisibleMadeToOrder({ ...listing, status: "active" })) {
        await assertSingleBuyerVisibleMadeToOrder(prisma, {
          sellerId: listing.sellerId,
          excludeListingId: listing.id,
        });
      }
    } catch (err) {
      return res.status(err.statusCode || 400).json({
        error: err.message,
        code: err.code,
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
