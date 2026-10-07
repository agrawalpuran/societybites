const { assertSellerSellingReachLevel } = require("./sellingReach");
const { assertSellerFulfilmentUpdate } = require("./sellerFulfilment");
const { assertSellerPaymentPreferenceUpdate, DEFAULT_PAYMENT_PREFERENCE } = require("./sellerPaymentPreference");

// Framework / Draft — Legal Review Required.
// Not legally approved or counsel approved. Qualified Indian legal counsel
// should review the seller terms wording before production use.
const SELLER_TERMS_VERSION = "1.0";

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function assertSellerTermsVersion(version) {
  if (version !== SELLER_TERMS_VERSION) {
    throw httpError(400, "Unsupported seller terms version");
  }
  return SELLER_TERMS_VERSION;
}

function assertAddressProofUrl(value, { required }) {
  if (value == null || String(value).trim() === "") {
    if (required) {
      throw httpError(400, "Address proof is required");
    }
    return undefined;
  }
  const text = String(value).trim();
  if (text.length > 2000 || !/^https:\/\//i.test(text)) {
    throw httpError(400, "Address proof is invalid");
  }
  return text;
}

/**
 * Records seller-terms acceptance and enables selling in one transaction.
 * acceptedAt is always generated here. Optional seller settings in `body`
 * are validated with the same rules as PATCH /auth/me/profile, using the
 * seller role that this call is about to grant.
 */
async function acceptSellerTermsAndEnable({ prisma, user, body }) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw httpError(400, "Seller terms acceptance requires a JSON body");
  }
  if (body.acceptedAt !== undefined) {
    throw httpError(400, "acceptedAt is recorded by the server");
  }
  const termsVersion = assertSellerTermsVersion(body.termsVersion);

  const enablingRole = user.role === "super_admin" ? "super_admin" : "seller";
  const becomingSeller = user.role !== "seller" && user.role !== "super_admin";
  const data = {};
  if (becomingSeller) {
    data.role = "seller";
  }

  const proofUrl = assertAddressProofUrl(body.addressProofUrl, {
    required: becomingSeller && !user.addressProofUrl,
  });
  if (proofUrl !== undefined) {
    data.addressProofUrl = proofUrl;
  }

  if (body.sellingReachLevel !== undefined) {
    let societyCity = null;
    if (user.societyId) {
      const society = await prisma.society.findUnique({
        where: { id: user.societyId },
        select: { city: true },
      });
      societyCity = society && society.city;
    }
    data.sellingReachLevel = await assertSellerSellingReachLevel({
      requested: body.sellingReachLevel,
      role: enablingRole,
      societyCity,
      prismaClient: prisma,
    });
  }

  if (
    body.fulfilmentMode !== undefined ||
    body.deliveryCharge !== undefined ||
    body.deliveryChargeInSociety !== undefined ||
    body.deliveryChargeNearby !== undefined ||
    body.deliveryChargeExtended !== undefined
  ) {
    const requestedMode =
      body.fulfilmentMode !== undefined
        ? body.fulfilmentMode
        : user.fulfilmentMode || "BUYER_PICKUP";
    const parsed = assertSellerFulfilmentUpdate({
      requestedMode,
      requestedCharge: body.deliveryCharge,
      requestedChargeInSociety: body.deliveryChargeInSociety,
      requestedChargeNearby: body.deliveryChargeNearby,
      requestedChargeExtended: body.deliveryChargeExtended,
      role: enablingRole,
    });
    if (body.fulfilmentMode !== undefined) data.fulfilmentMode = parsed.fulfilmentMode;
    if (parsed.deliveryCharge !== undefined) data.deliveryCharge = parsed.deliveryCharge;
    if (parsed.deliveryChargeInSociety !== undefined) {
      data.deliveryChargeInSociety = parsed.deliveryChargeInSociety;
    }
    if (parsed.deliveryChargeNearby !== undefined) {
      data.deliveryChargeNearby = parsed.deliveryChargeNearby;
    }
    if (parsed.deliveryChargeExtended !== undefined) {
      data.deliveryChargeExtended = parsed.deliveryChargeExtended;
    }
  }

  if (body.upiId !== undefined) {
    const trimmed = typeof body.upiId === "string" ? body.upiId.trim() : body.upiId;
    if (trimmed === "" || trimmed === null) {
      data.upiId = null;
      data.paymentEnabled = false;
    } else {
      if (!String(trimmed).includes("@")) {
        throw httpError(400, "UPI ID must look like name@bank");
      }
      data.upiId = String(trimmed);
      data.paymentEnabled = true;
    }
  }
  if (body.upiDisplayName !== undefined) {
    data.upiDisplayName =
      typeof body.upiDisplayName === "string" && body.upiDisplayName.trim()
        ? body.upiDisplayName.trim()
        : null;
  }
  if (body.paymentPreference !== undefined) {
    data.paymentPreference = assertSellerPaymentPreferenceUpdate({
      requested: body.paymentPreference,
      role: enablingRole,
    });
  } else if (user.role !== "seller" && user.role !== "super_admin") {
    data.paymentPreference = DEFAULT_PAYMENT_PREFERENCE;
  }
  const acceptedAt = new Date();
  return prisma.$transaction(async (tx) => {
    const existing = await tx.sellerTermsAcceptance.findUnique({
      where: {
        userId_termsVersion: { userId: user.id, termsVersion },
      },
    });
    const acceptance = existing
      ? existing
      : await tx.sellerTermsAcceptance.create({
          data: {
            userId: user.id,
            termsVersion,
            acceptedAt,
          },
        });
    const updated = Object.keys(data).length
      ? await tx.user.update({
          where: { id: user.id },
          data,
          include: { society: true, flat: true },
        })
      : await tx.user.findUnique({
          where: { id: user.id },
          include: { society: true, flat: true },
        });
    return { user: updated, acceptance };
  });
}

module.exports = {
  SELLER_TERMS_VERSION,
  assertSellerTermsVersion,
  acceptSellerTermsAndEnable,
};
