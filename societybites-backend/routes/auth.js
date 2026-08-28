const express = require("express");
const prisma = require("../lib/prisma");
const { getAuth } = require("../lib/firebase");
const { signToken, signAccessToken, ACCESS_TOKEN_EXPIRY } = require("../lib/jwt");
const { asyncHandler } = require("../utils/asyncHandler");
const { requireUser } = require("../middleware/requireUser");
const { normalizeIndianPhone, toTwoFactorPhone } = require("../utils/phone");
const twoFactor = require("../lib/twoFactor");
const otpStore = require("../lib/otpStore");
const { isTestPhone, canonicalTestPhone, otpMatches } = require("../lib/testOtp");
const {
  issueRefreshToken,
  rotateRefreshToken,
  revokeRefreshToken,
} = require("../lib/refreshTokens");
const { rateLimit } = require("../middleware/rateLimit");

const router = express.Router();

const otpIpLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: Number(process.env.OTP_IP_MAX) || 20,
});

function resolveLoginPhone(raw) {
  return normalizeIndianPhone(raw) || canonicalTestPhone(raw);
}

function serializeAuthUser(user) {
  return {
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
  };
}

const userInclude = { society: true, flat: true };

async function findOrCreateUserByPhone(phone) {
  let user = await prisma.user.findUnique({
    where: { phone },
    include: userInclude,
  });

  if (!user) {
    user = await prisma.user.create({
      data: { phone, role: "buyer" },
      include: userInclude,
    });
  }

  return user;
}

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

router.post(
  "/send-otp",
  otpIpLimit,
  asyncHandler(async (req, res) => {
    const phone = resolveLoginPhone(req.body?.phone);
    if (!phone) {
      return res.status(400).json({ error: "Enter a valid 10-digit Indian mobile number" });
    }

    const allowed = otpStore.canSend(phone);
    if (!allowed.ok) {
      return res.status(allowed.status).json({ error: allowed.error });
    }

    if (isTestPhone(phone)) {
      otpStore.saveSend(phone, "test");
      return res.json({ ok: true, message: "OTP sent" });
    }

    const tfPhone = toTwoFactorPhone(phone);
    const { sessionId } = await twoFactor.sendOtp(tfPhone);
    otpStore.saveSend(phone, sessionId);

    res.json({ ok: true, message: "OTP sent" });
  })
);

router.post(
  "/verify-otp",
  otpIpLimit,
  asyncHandler(async (req, res) => {
    const phone = resolveLoginPhone(req.body?.phone);
    const otp = typeof req.body?.otp === "string" ? req.body.otp.trim() : "";

    if (!phone) {
      return res.status(400).json({ error: "Enter a valid 10-digit Indian mobile number" });
    }
    if (!/^\d{4,8}$/.test(otp)) {
      return res.status(400).json({ error: "Enter a valid OTP" });
    }

    const challenge = otpStore.get(phone);
    if (!challenge) {
      return res.status(400).json({ error: "OTP expired or not requested. Please request a new code." });
    }

    if (otpStore.tooManyAttempts(challenge)) {
      otpStore.consume(phone);
      return res.status(429).json({ error: "Too many incorrect attempts. Request a new OTP." });
    }

    const { matched } = isTestPhone(phone)
      ? { matched: otpMatches(otp) }
      : await twoFactor.verifyOtp(challenge.sessionId, otp);
    if (!matched) {
      const attempted = otpStore.recordAttempt(phone);
      if (attempted && otpStore.tooManyAttempts(attempted)) {
        otpStore.consume(phone);
        return res.status(429).json({ error: "Too many incorrect attempts. Request a new OTP." });
      }
      return res.status(401).json({ error: "Invalid OTP" });
    }

    otpStore.consume(phone);

    const user = await findOrCreateUserByPhone(phone);
    if (user.suspended) {
      return res.status(403).json({ error: "Account suspended" });
    }

    const token = signAccessToken(user);
    const { refreshToken } = await issueRefreshToken(user.id);

    res.json({
      success: true,
      token,
      refreshToken,
      expiresIn: ACCESS_TOKEN_EXPIRY,
      user: serializeAuthUser(user),
    });
  })
);

router.post(
  "/refresh",
  asyncHandler(async (req, res) => {
    const raw =
      typeof req.body?.refreshToken === "string" ? req.body.refreshToken.trim() : "";
    if (!raw) {
      return res.status(400).json({ error: "refreshToken is required" });
    }

    const rotated = await rotateRefreshToken(raw);
    if (rotated.error) {
      return res.status(rotated.status).json({ error: rotated.error });
    }

    const user = await prisma.user.findUnique({
      where: { id: rotated.userId },
      include: userInclude,
    });

    if (!user) {
      return res.status(401).json({ error: "User not found" });
    }
    if (user.suspended) {
      return res.status(403).json({ error: "Account suspended" });
    }

    const token = signAccessToken(user);
    res.json({
      success: true,
      token,
      refreshToken: rotated.refreshToken,
      expiresIn: ACCESS_TOKEN_EXPIRY,
      user: serializeAuthUser(user),
    });
  })
);

router.post(
  "/logout",
  asyncHandler(async (req, res) => {
    const raw =
      typeof req.body?.refreshToken === "string" ? req.body.refreshToken.trim() : "";
    await revokeRefreshToken(raw);
    res.json({ ok: true });
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
    const {
      name,
      role,
      profilePhotoUrl,
      upiId,
      upiDisplayName,
      paymentEnabled,
    } = req.body;

    const data = {};
    if (name !== undefined) data.name = name;
    if (role !== undefined && ["buyer", "seller"].includes(role)) data.role = role;
    // societyId / flatId are assigned only via POST /societies/join.
    if (profilePhotoUrl !== undefined) data.profilePhotoUrl = profilePhotoUrl;
    if (upiId !== undefined) {
      const trimmed = typeof upiId === "string" ? upiId.trim() : upiId;
      if (trimmed === "" || trimmed === null) {
        data.upiId = null;
        data.paymentEnabled = false;
      } else {
        if (!String(trimmed).includes("@")) {
          return res.status(400).json({ error: "UPI ID must look like name@bank" });
        }
        data.upiId = String(trimmed);
        data.paymentEnabled = true;
      }
    }
    if (upiDisplayName !== undefined) {
      data.upiDisplayName =
        typeof upiDisplayName === "string" && upiDisplayName.trim()
          ? upiDisplayName.trim()
          : null;
    }
    if (paymentEnabled !== undefined && upiId === undefined) {
      data.paymentEnabled = Boolean(paymentEnabled);
    }

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
