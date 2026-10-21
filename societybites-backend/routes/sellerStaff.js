const express = require("express");
const prisma = require("../lib/prisma");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const {
  inviteOwnerByPhone,
  listOwnersForSeller,
  listStaffAccessForUser,
  canManageOwnerAccess,
} = require("../lib/sellerStaff");

const router = express.Router();

/** Manager: owners who can view this kitchen (no revoke in MVP). */
router.get(
  "/owners",
  requireUser,
  asyncHandler(async (req, res) => {
    if (!canManageOwnerAccess(req.user)) {
      return res.status(403).json({
        error: "Enable selling before managing owner access",
        code: "SELLER_REQUIRED",
      });
    }
    const owners = await listOwnersForSeller(prisma, req.user.id);
    res.json({ owners });
  })
);

/** Manager: invite an owner by phone (view-only). */
router.post(
  "/owners/invite",
  requireUser,
  asyncHandler(async (req, res) => {
    try {
      const membership = await inviteOwnerByPhone(prisma, {
        sellerUser: req.user,
        phoneRaw: req.body && req.body.phone,
      });
      res.status(201).json({ membership });
    } catch (err) {
      const statusCode = err.statusCode || 500;
      return res.status(statusCode).json({
        error: statusCode === 500 ? "Internal server error" : err.message,
        code: err.code,
      });
    }
  })
);

/** Any user: kitchens they may oversee (owner view-only). */
router.get(
  "/access",
  requireUser,
  asyncHandler(async (req, res) => {
    const staffAccess = await listStaffAccessForUser(prisma, req.user.id);
    res.json({ staffAccess });
  })
);

module.exports = router;
