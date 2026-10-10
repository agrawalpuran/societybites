const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { requireAdmin, requireSuperAdmin } = require("../middleware/requireAdmin");
const { normalizeIndianPhone } = require("../utils/phone");
const {
  repairLegacyConsoleAdminSeller,
  isConsoleAdminUser,
} = require("../lib/consoleAdmin");
const {
  listAdminIssues,
  getAdminIssue,
  updateAdminIssue,
} = require("../lib/issueReports");
const {
  createCoupon,
  listCoupons,
  getCoupon,
  updateCoupon,
  setCouponStatus,
  assignEligibleUsers,
} = require("../lib/coupons");
const { canonicalCityKey } = require("../lib/launchCity");
const { validateCityReachRadii } = require("../lib/sellingReach");
const {
  getAdminFssaiSummary,
  listAdminFssaiSubmissions,
  getAdminFssaiDocumentUrl,
  approveAdminFssai,
  rejectAdminFssai,
  listAdminFssaiAssistance,
  getAdminFssaiAssistanceDetail,
  updateAdminFssaiAssistance,
  REJECTION_PRESETS,
} = require("../lib/fssaiCompliance");
const {
  isFssaiSellingRequirementEnabled,
  setFssaiSellingRequirement,
} = require("../lib/fssaiRequirement");
const { listCouponSellerPayouts } = require("../lib/couponRecon");
const {
  listAddressProofs,
  getAddressProof,
  reviewAddressProof,
} = require("../lib/addressProofReview");

const router = express.Router();

router.use(requireUser, requireAdmin);

router.use((req, res, next) => {
  if (req.method === "GET" || req.method === "HEAD") {
    return next();
  }
  return requireSuperAdmin(req, res, next);
});

// GET /admin/console-admins — super admin only (not exposed to view-only admins)
router.get(
  "/console-admins",
  requireSuperAdmin,
  asyncHandler(async (_req, res) => {
    const admins = await prisma.user.findMany({
      where: {
        OR: [{ consoleAdmin: true }, { role: "admin" }],
      },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        name: true,
        phone: true,
        role: true,
        consoleAdmin: true,
        suspended: true,
        createdAt: true,
        society: { select: { name: true } },
      },
    });
    for (let i = 0; i < admins.length; i++) {
      if (admins[i].role === "admin" && !admins[i].consoleAdmin) {
        admins[i] = await repairLegacyConsoleAdminSeller(admins[i], {
          society: { select: { name: true } },
        });
      }
    }
    res.json({ admins });
  })
);

// POST /admin/console-admins { phone } — grant view-only console access
router.post(
  "/console-admins",
  asyncHandler(async (req, res) => {
    const phone = normalizeIndianPhone(req.body && req.body.phone);
    if (!phone) {
      return res.status(400).json({ error: "Valid Indian mobile number required" });
    }

    const user = await prisma.user.findUnique({ where: { phone } });
    if (!user) {
      return res.status(404).json({ error: "No user found with this mobile number" });
    }
    if (user.role === "super_admin") {
      return res.status(400).json({ error: "User is already a super admin" });
    }
    if (user.suspended) {
      return res.status(400).json({
        error: "Cannot grant console access to a suspended user",
      });
    }
    if (user.consoleAdmin) {
      return res.json({ user, alreadyAdmin: true });
    }
    if (user.role === "admin") {
      const repaired = await repairLegacyConsoleAdminSeller(user, {
        society: true,
        flat: true,
      });
      return res.json({ user: repaired, alreadyAdmin: true });
    }

    const updated = await prisma.user.update({
      where: { id: user.id },
      data: { consoleAdmin: true },
      include: { society: true, flat: true },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "grant_console_admin",
        target: user.id,
        details: JSON.stringify({ phone }),
      },
    });

    res.json({ user: updated });
  })
);

// DELETE /admin/console-admins/:userId — revoke view-only console access
router.delete(
  "/console-admins/:userId",
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({ where: { id: req.params.userId } });
    if (!user) {
      return res.status(404).json({ error: "User not found" });
    }
    if (!isConsoleAdminUser(user)) {
      return res.status(400).json({ error: "User is not a console admin" });
    }

    const data = { consoleAdmin: false };
    if (user.role === "admin") {
      data.role = "buyer";
    }

    const updated = await prisma.user.update({
      where: { id: user.id },
      data,
      include: { society: true, flat: true },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "revoke_console_admin",
        target: user.id,
        details: JSON.stringify({ phone: user.phone }),
      },
    });

    res.json({ user: updated });
  })
);

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

router.get(
  "/fssai/summary",
  asyncHandler(async (_req, res) => {
    const summary = await getAdminFssaiSummary();
    res.json(summary);
  })
);

router.get(
  "/fssai/submissions",
  asyncHandler(async (req, res) => {
    const records = await listAdminFssaiSubmissions({ status: req.query.status });
    res.json({ records });
  })
);

router.get(
  "/fssai/submissions/:sellerId/document-url",
  asyncHandler(async (req, res) => {
    const payload = await getAdminFssaiDocumentUrl(req.user, req.params.sellerId);
    res.json(payload);
  })
);

router.post(
  "/fssai/submissions/:sellerId/approve",
  asyncHandler(async (req, res) => {
    const fssai = await approveAdminFssai(req.user, req.params.sellerId);
    res.json({ fssai });
  })
);

router.post(
  "/fssai/submissions/:sellerId/reject",
  asyncHandler(async (req, res) => {
    const fssai = await rejectAdminFssai(req.user, req.params.sellerId, req.body);
    res.json({ fssai, rejectionPresets: REJECTION_PRESETS });
  })
);

router.get(
  "/address-proofs",
  asyncHandler(async (req, res) => {
    const records = await listAddressProofs({ status: req.query.status });
    res.json({ records });
  })
);

router.get(
  "/address-proofs/:userId",
  asyncHandler(async (req, res) => {
    const record = await getAddressProof(req.params.userId);
    res.json({ record });
  })
);

router.post(
  "/address-proofs/:userId/review",
  asyncHandler(async (req, res) => {
    const record = await reviewAddressProof({
      adminUser: req.user,
      userId: req.params.userId,
      status: req.body && req.body.status,
    });
    res.json({ record });
  })
);

router.get(
  "/fssai/assistance",
  asyncHandler(async (req, res) => {
    const requests = await listAdminFssaiAssistance({ status: req.query.status });
    res.json({ requests });
  })
);

router.get(
  "/fssai/assistance/:id",
  asyncHandler(async (req, res) => {
    const request = await getAdminFssaiAssistanceDetail(req.params.id);
    res.json({ request });
  })
);

router.patch(
  "/fssai/assistance/:id",
  asyncHandler(async (req, res) => {
    const request = await updateAdminFssaiAssistance(
      req.params.id,
      req.body,
      req.user
    );
    const detail = await getAdminFssaiAssistanceDetail(request.id);
    res.json({ request: detail });
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
      const validRoles = ["buyer", "seller", "admin"];
      if (!validRoles.includes(role)) {
        return res.status(400).json({
          error: "Invalid role. Must be one of: buyer, seller, admin",
        });
      }
      if (req.user.role !== "super_admin") {
        return res.status(403).json({ error: "Super admin access required" });
      }
      const target = await prisma.user.findUnique({
        where: { id: req.params.id },
        select: { role: true },
      });
      if (!target) {
        return res.status(404).json({ error: "User not found" });
      }
      if (target.role === "super_admin") {
        return res.status(400).json({ error: "Cannot change a super admin role" });
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
          items: {
            include: {
              listing: {
                select: {
                  id: true,
                  name: true,
                  sellerId: true,
                  seller: { select: { id: true, name: true, phone: true } },
                },
              },
            },
          },
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
    const fssaiSellingRequirement = await isFssaiSellingRequirementEnabled();
    res.json({ platformFee, fssaiSellingRequirement });
  })
);

// PATCH /admin/settings
router.patch(
  "/settings",
  asyncHandler(async (req, res) => {
    const { setPlatformFee } = require("../lib/platformFee");
    const { platformFee, fssaiSellingRequirement } = req.body;

    const updates = {};
    if (platformFee !== undefined && platformFee !== null) {
      updates.platformFee = await setPlatformFee(platformFee);
    }
    if (fssaiSellingRequirement !== undefined) {
      updates.fssaiSellingRequirement = await setFssaiSellingRequirement(
        Boolean(fssaiSellingRequirement)
      );
    }
    if (!Object.keys(updates).length) {
      return res.status(400).json({ error: "Nothing to update" });
    }

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: "UPDATE_ADMIN_SETTINGS",
        target: "settings",
        details: JSON.stringify(updates),
      },
    });

    res.json({
      platformFee: updates.platformFee ?? (await require("../lib/platformFee").getPlatformFee()),
      fssaiSellingRequirement:
        updates.fssaiSellingRequirement ?? (await isFssaiSellingRequirementEnabled()),
    });
  })
);

function displayNameFromCityKey(cityKey, provided) {
  if (typeof provided === "string" && provided.trim()) return provided.trim();
  if (!cityKey) return cityKey;
  return cityKey.charAt(0).toUpperCase() + cityKey.slice(1);
}

// GET /admin/city-reach-configs
router.get(
  "/city-reach-configs",
  asyncHandler(async (_req, res) => {
    const configs = await prisma.cityReachConfig.findMany({
      orderBy: { cityKey: "asc" },
    });
    res.json(configs);
  })
);

// PUT /admin/city-reach-configs/:cityKey
router.put(
  "/city-reach-configs/:cityKey",
  asyncHandler(async (req, res) => {
    const cityKey = canonicalCityKey(req.params.cityKey);
    if (!cityKey) {
      return res.status(400).json({ error: "cityKey is required" });
    }

    const { nearbyRadiusKm, extendedRadiusKm } = validateCityReachRadii(req.body || {});
    const existing = await prisma.cityReachConfig.findUnique({ where: { cityKey } });
    const displayName = displayNameFromCityKey(cityKey, req.body && req.body.displayName);

    const config = await prisma.cityReachConfig.upsert({
      where: { cityKey },
      update: { displayName, nearbyRadiusKm, extendedRadiusKm },
      create: { cityKey, displayName, nearbyRadiusKm, extendedRadiusKm },
    });

    await prisma.auditLog.create({
      data: {
        adminId: req.user.id,
        action: existing ? "UPDATE_CITY_REACH_CONFIG" : "CREATE_CITY_REACH_CONFIG",
        target: cityKey,
        details: JSON.stringify({
          cityKey,
          displayName,
          nearbyRadiusKm,
          extendedRadiusKm,
        }),
      },
    });

    res.json(config);
  })
);

router.get(
  "/issues",
  asyncHandler(async (req, res) => {
    const issues = await listAdminIssues(req.query.status);
    res.json({ issues });
  })
);

router.get(
  "/issues/:id",
  asyncHandler(async (req, res) => {
    const issue = await getAdminIssue(req.params.id);
    res.json(issue);
  })
);

router.patch(
  "/issues/:id",
  asyncHandler(async (req, res) => {
    const issue = await updateAdminIssue(req.params.id, req.body, req.user);
    res.json(issue);
  })
);

router.get(
  "/reports/coupon-seller-payouts",
  asyncHandler(async (req, res) => {
    const report = await listCouponSellerPayouts({
      dateFrom: req.query.dateFrom,
      dateTo: req.query.dateTo,
      sellerId: req.query.sellerId,
    });
    res.json(report);
  })
);

router.post(
  "/coupons",
  asyncHandler(async (req, res) => {
    const coupon = await createCoupon(req.body);
    res.status(201).json(coupon);
  })
);

router.get(
  "/coupons",
  asyncHandler(async (req, res) => {
    const coupons = await listCoupons();
    res.json({ coupons });
  })
);

router.get(
  "/coupons/:id",
  asyncHandler(async (req, res) => {
    const coupon = await getCoupon(req.params.id);
    res.json(coupon);
  })
);

router.patch(
  "/coupons/:id",
  asyncHandler(async (req, res) => {
    const coupon = await updateCoupon(req.params.id, req.body);
    res.json(coupon);
  })
);

router.post(
  "/coupons/:id/pause",
  asyncHandler(async (req, res) => {
    const coupon = await setCouponStatus(req.params.id, "PAUSED");
    res.json(coupon);
  })
);

router.post(
  "/coupons/:id/activate",
  asyncHandler(async (req, res) => {
    const coupon = await setCouponStatus(req.params.id, "ACTIVE");
    res.json(coupon);
  })
);

router.put(
  "/coupons/:id/eligible-users",
  asyncHandler(async (req, res) => {
    const coupon = await assignEligibleUsers(req.params.id, req.body && req.body.userIds);
    res.json(coupon);
  })
);

module.exports = router;
