const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { requireAdmin } = require("../middleware/requireAdmin");

const router = express.Router();

router.use(requireUser, requireAdmin);

// GET /admin/dashboard
router.get(
  "/dashboard",
  asyncHandler(async (req, res) => {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    const [
      totalUsers,
      totalSellers,
      totalBuyers,
      totalSocieties,
      activeListings,
      soldOutListings,
      totalOrders,
      todayOrders,
      pendingOrders,
      completedOrders,
      cancelledOrders,
      totalReviews,
      ratingAgg,
    ] = await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { role: "seller" } }),
      prisma.user.count({ where: { role: "buyer" } }),
      prisma.society.count(),
      prisma.listing.count({ where: { status: "active" } }),
      prisma.listing.count({ where: { status: "sold_out" } }),
      prisma.order.count(),
      prisma.order.count({ where: { createdAt: { gte: todayStart } } }),
      prisma.order.count({ where: { status: "pending" } }),
      prisma.order.count({ where: { status: "completed" } }),
      prisma.order.count({ where: { status: "cancelled" } }),
      prisma.review.count(),
      prisma.review.aggregate({ _avg: { rating: true } }),
    ]);

    res.json({
      totalUsers,
      totalSellers,
      totalBuyers,
      totalSocieties,
      activeListings,
      soldOutListings,
      totalOrders,
      todayOrders,
      pendingOrders,
      completedOrders,
      cancelledOrders,
      totalReviews,
      avgPlatformRating: ratingAgg._avg.rating || 0,
    });
  })
);

// GET /admin/users
router.get(
  "/users",
  asyncHandler(async (req, res) => {
    const { search, role, societyId, page = 1, limit = 50 } = req.query;
    const take = parseInt(limit, 10);
    const skip = (parseInt(page, 10) - 1) * take;

    const where = {
      ...(role && { role: String(role) }),
      ...(societyId && { societyId: String(societyId) }),
      ...(search && {
        OR: [
          { name: { contains: String(search), mode: "insensitive" } },
          { phone: { contains: String(search), mode: "insensitive" } },
        ],
      }),
    };

    const [users, total] = await Promise.all([
      prisma.user.findMany({
        where,
        include: { society: true, flat: true },
        orderBy: { createdAt: "desc" },
        skip,
        take,
      }),
      prisma.user.count({ where }),
    ]);

    res.json({ users, total, page: parseInt(page, 10), limit: take });
  })
);

// PATCH /admin/users/:id
router.patch(
  "/users/:id",
  asyncHandler(async (req, res) => {
    const { role, suspended } = req.body;
    const data = {};

    if (role !== undefined) {
      const validRoles = ["buyer", "seller", "super_admin"];
      if (!validRoles.includes(role)) {
        return res.status(400).json({ error: "Invalid role. Must be one of: buyer, seller, super_admin" });
      }
      data.role = role;
    }

    if (suspended !== undefined) {
      data.suspended = Boolean(suspended);
    }

    if (Object.keys(data).length === 0) {
      return res.status(400).json({ error: "No valid fields to update" });
    }

    const user = await prisma.user.update({
      where: { id: req.params.id },
      data,
      include: { society: true, flat: true },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "update_user",
        target: req.params.id,
        details: JSON.stringify(data),
      },
    });

    res.json(user);
  })
);

// GET /admin/societies
router.get(
  "/societies",
  asyncHandler(async (req, res) => {
    const societies = await prisma.society.findMany({
      include: {
        _count: {
          select: {
            users: true,
            listings: true,
            orders: true,
          },
        },
      },
      orderBy: { name: "asc" },
    });

    const result = societies.map((s) => {
      const { _count, ...rest } = s;
      return {
        ...rest,
        membersCount: _count.users,
        listingsCount: _count.listings,
        ordersCount: _count.orders,
      };
    });

    res.json(result);
  })
);

// POST /admin/societies
router.post(
  "/societies",
  asyncHandler(async (req, res) => {
    const { name, city, inviteCode, address, state, pincode } = req.body;

    if (!name || !city || !inviteCode) {
      return res.status(400).json({ error: "name, city, and inviteCode are required" });
    }

    const society = await prisma.society.create({
      data: { name, city, inviteCode, address, state, pincode },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "create_society",
        target: society.id,
        details: JSON.stringify({ name, city }),
      },
    });

    res.status(201).json(society);
  })
);

// PATCH /admin/societies/:id
router.patch(
  "/societies/:id",
  asyncHandler(async (req, res) => {
    const { name, city, inviteCode, address, state, pincode, status } = req.body;

    const data = {
      ...(name !== undefined && { name }),
      ...(city !== undefined && { city }),
      ...(inviteCode !== undefined && { inviteCode }),
      ...(address !== undefined && { address }),
      ...(state !== undefined && { state }),
      ...(pincode !== undefined && { pincode }),
      ...(status !== undefined && { status }),
    };

    if (Object.keys(data).length === 0) {
      return res.status(400).json({ error: "No valid fields to update" });
    }

    const society = await prisma.society.update({
      where: { id: req.params.id },
      data,
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "update_society",
        target: req.params.id,
        details: JSON.stringify(data),
      },
    });

    res.json(society);
  })
);

// POST /admin/societies/:id/regenerate-code
router.post(
  "/societies/:id/regenerate-code",
  asyncHandler(async (req, res) => {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let newCode = "";
    for (let i = 0; i < 8; i++) {
      newCode += chars.charAt(Math.floor(Math.random() * chars.length));
    }

    const society = await prisma.society.update({
      where: { id: req.params.id },
      data: { inviteCode: newCode },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "regenerate_invite_code",
        target: req.params.id,
        details: JSON.stringify({ newCode }),
      },
    });

    res.json({ inviteCode: newCode, society });
  })
);

// GET /admin/listings
router.get(
  "/listings",
  asyncHandler(async (req, res) => {
    const { search, societyId, sellerId, status, page = 1, limit = 50 } = req.query;
    const take = parseInt(limit, 10);
    const skip = (parseInt(page, 10) - 1) * take;

    const where = {
      ...(societyId && { societyId: String(societyId) }),
      ...(sellerId && { sellerId: String(sellerId) }),
      ...(status && { status: String(status) }),
      ...(search && {
        name: { contains: String(search), mode: "insensitive" },
      }),
    };

    const [listings, total] = await Promise.all([
      prisma.listing.findMany({
        where,
        include: { seller: { select: { id: true, name: true, phone: true } }, society: true },
        orderBy: { createdAt: "desc" },
        skip,
        take,
      }),
      prisma.listing.count({ where }),
    ]);

    res.json({ listings, total, page: parseInt(page, 10), limit: take });
  })
);

// PATCH /admin/listings/:id
router.patch(
  "/listings/:id",
  asyncHandler(async (req, res) => {
    const { status, featured } = req.body;

    const data = {
      ...(status !== undefined && { status }),
      ...(featured !== undefined && { featured: Boolean(featured) }),
    };

    if (Object.keys(data).length === 0) {
      return res.status(400).json({ error: "No valid fields to update" });
    }

    const listing = await prisma.listing.update({
      where: { id: req.params.id },
      data,
      include: { seller: { select: { id: true, name: true, phone: true } } },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "update_listing",
        target: req.params.id,
        details: JSON.stringify(data),
      },
    });

    res.json(listing);
  })
);

// GET /admin/orders
router.get(
  "/orders",
  asyncHandler(async (req, res) => {
    const { societyId, sellerId, buyerId, status, dateFrom, dateTo, page = 1, limit = 50 } = req.query;
    const take = parseInt(limit, 10);
    const skip = (parseInt(page, 10) - 1) * take;

    const where = {
      ...(societyId && { societyId: String(societyId) }),
      ...(buyerId && { buyerId: String(buyerId) }),
      ...(status && { status: String(status) }),
      ...(sellerId && {
        items: { some: { listing: { sellerId: String(sellerId) } } },
      }),
      ...((dateFrom || dateTo) && {
        createdAt: {
          ...(dateFrom && { gte: new Date(dateFrom) }),
          ...(dateTo && { lte: new Date(dateTo) }),
        },
      }),
    };

    const [orders, total] = await Promise.all([
      prisma.order.findMany({
        where,
        include: {
          buyer: { select: { id: true, name: true, phone: true } },
          items: { include: { listing: { select: { id: true, name: true, sellerId: true } } } },
        },
        orderBy: { createdAt: "desc" },
        skip,
        take,
      }),
      prisma.order.count({ where }),
    ]);

    res.json({ orders, total, page: parseInt(page, 10), limit: take });
  })
);

// GET /admin/reviews
router.get(
  "/reviews",
  asyncHandler(async (req, res) => {
    const { listingId, page = 1, limit = 50 } = req.query;
    const take = parseInt(limit, 10);
    const skip = (parseInt(page, 10) - 1) * take;

    const where = {
      ...(listingId && { listingId: String(listingId) }),
    };

    const [reviews, total] = await Promise.all([
      prisma.review.findMany({
        where,
        include: {
          reviewer: { select: { id: true, name: true, phone: true } },
          listing: { select: { id: true, name: true } },
        },
        orderBy: { createdAt: "desc" },
        skip,
        take,
      }),
      prisma.review.count({ where }),
    ]);

    res.json({ reviews, total, page: parseInt(page, 10), limit: take });
  })
);

// PATCH /admin/reviews/:id
router.patch(
  "/reviews/:id",
  asyncHandler(async (req, res) => {
    const { hidden } = req.body;

    if (hidden === undefined) {
      return res.status(400).json({ error: "hidden field is required" });
    }

    const review = await prisma.review.update({
      where: { id: req.params.id },
      data: { hidden: Boolean(hidden) },
      include: {
        reviewer: { select: { id: true, name: true } },
        listing: { select: { id: true, name: true } },
      },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "update_review",
        target: req.params.id,
        details: JSON.stringify({ hidden: Boolean(hidden) }),
      },
    });

    res.json(review);
  })
);

// GET /admin/payments
router.get(
  "/payments",
  asyncHandler(async (req, res) => {
    const { status, societyId, page = 1, limit = 50 } = req.query;
    const take = parseInt(limit, 10);
    const skip = (parseInt(page, 10) - 1) * take;

    const where = {
      ...(status && { paymentStatus: String(status) }),
      ...(societyId && { societyId: String(societyId) }),
    };

    const [orders, total] = await Promise.all([
      prisma.order.findMany({
        where,
        select: {
          id: true,
          orderNumber: true,
          total: true,
          paymentMethod: true,
          paymentStatus: true,
          buyerMarkedPaidAt: true,
          sellerConfirmedPaidAt: true,
          upiTransactionRef: true,
          createdAt: true,
          buyer: { select: { id: true, name: true, phone: true } },
          society: { select: { id: true, name: true } },
        },
        orderBy: { createdAt: "desc" },
        skip,
        take,
      }),
      prisma.order.count({ where }),
    ]);

    res.json({ orders, total, page: parseInt(page, 10), limit: take });
  })
);

// GET /admin/audit-log
router.get(
  "/audit-log",
  asyncHandler(async (req, res) => {
    const { page = 1, limit = 50, adminId } = req.query;
    const take = parseInt(limit, 10);
    const skip = (parseInt(page, 10) - 1) * take;

    const where = {
      ...(adminId && { adminId: String(adminId) }),
    };

    const [logs, total] = await Promise.all([
      prisma.auditLog.findMany({
        where,
        include: { admin: { select: { id: true, name: true } } },
        orderBy: { createdAt: "desc" },
        skip,
        take,
      }),
      prisma.auditLog.count({ where }),
    ]);

    res.json({ logs, total, page: parseInt(page, 10), limit: take });
  })
);

// GET /admin/search
router.get(
  "/search",
  asyncHandler(async (req, res) => {
    const { q } = req.query;

    if (!q || !String(q).trim()) {
      return res.status(400).json({ error: "q query param is required" });
    }

    const term = String(q).trim();

    const [users, listings, orders, societies] = await Promise.all([
      prisma.user.findMany({
        where: {
          OR: [
            { name: { contains: term, mode: "insensitive" } },
            { phone: { contains: term, mode: "insensitive" } },
          ],
        },
        select: { id: true, name: true, phone: true, role: true },
        take: 10,
      }),
      prisma.listing.findMany({
        where: { name: { contains: term, mode: "insensitive" } },
        select: { id: true, name: true, status: true, sellerId: true },
        take: 10,
      }),
      prisma.order.findMany({
        where: { orderNumber: { contains: term, mode: "insensitive" } },
        select: { id: true, orderNumber: true, status: true, total: true },
        take: 10,
      }),
      prisma.society.findMany({
        where: { name: { contains: term, mode: "insensitive" } },
        select: { id: true, name: true, city: true },
        take: 10,
      }),
    ]);

    res.json({ users, listings, orders, societies });
  })
);

// GET /admin/settings
router.get(
  "/settings",
  asyncHandler(async (_req, res) => {
    const { getPlatformFee } = require("../lib/platformFee");
    const platformFee = await getPlatformFee();
    res.json({ platformFee });
  })
);

// PATCH /admin/settings
router.patch(
  "/settings",
  asyncHandler(async (req, res) => {
    const { setPlatformFee } = require("../lib/platformFee");
    const { platformFee } = req.body;

    if (platformFee === undefined || platformFee === null) {
      return res.status(400).json({ error: "platformFee is required" });
    }

    const value = await setPlatformFee(platformFee);

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "UPDATE_PLATFORM_FEE",
        target: "settings",
        details: JSON.stringify({ platformFee: value }),
      },
    });

    res.json({ platformFee: value });
  })
);

module.exports = router;
