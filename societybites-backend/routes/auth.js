const express = require("express");
const prisma = require("../lib/prisma");
const { getAuth } = require("../lib/firebase");
const { signToken } = require("../lib/jwt");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");

const router = express.Router();

router.post(
  "/firebase-login",
  asyncHandler(async (req, res) => {
    const { firebaseToken } = req.body;

    if (!firebaseToken) {
      return res.status(400).json({ error: "firebaseToken is required" });
    }

    let decodedToken;
    try {
      decodedToken = await getAuth().verifyIdToken(firebaseToken);
    } catch (err) {
      return res.status(401).json({ error: "Invalid or expired Firebase token" });
    }

    const phone = decodedToken.phone_number;
    if (!phone) {
      return res.status(400).json({ error: "Firebase token does not contain a phone number" });
    }

    let user = await prisma.user.findUnique({
      where: { phone },
      include: { society: true, flat: true },
    });

    if (!user) {
      user = await prisma.user.create({
        data: { phone, role: "buyer" },
        include: { society: true, flat: true },
      });
    }

    const token = signToken(user);

    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        phone: user.phone,
        name: user.name,
        role: user.role,
        profilePhotoUrl: user.profilePhotoUrl,
        upiId: user.upiId,
        societyId: user.societyId,
        flatId: user.flatId,
        society: user.society,
        flat: user.flat,
        inviteCode: user.society ? user.society.inviteCode : null,
        createdAt: user.createdAt,
      },
    });
  })
);

router.get(
  "/me",
  requireUser,
  asyncHandler(async (req, res) => {
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      include: { society: true, flat: true },
    });

    res.json(user);
  })
);

router.patch(
  "/me/profile",
  requireUser,
  asyncHandler(async (req, res) => {
    const { name, role, societyId, flatId, profilePhotoUrl, upiId } = req.body;

    const data = {};
    if (name !== undefined) data.name = name;
    if (role !== undefined && ["buyer", "seller"].includes(role)) data.role = role;
    if (societyId !== undefined) data.societyId = societyId;
    if (flatId !== undefined) data.flatId = flatId;
    if (profilePhotoUrl !== undefined) data.profilePhotoUrl = profilePhotoUrl;
    if (upiId !== undefined) data.upiId = upiId;

    const user = await prisma.user.update({
      where: { id: req.user.id },
      data,
      include: { society: true, flat: true },
    });

    const token = signToken(user);

    res.json({ user, token });
  })
);

module.exports = router;
