const prisma = require("./prisma");

/**
 * Privacy-preserving account deletion for SocietyBites.
 *
 * The User row is retained (anonymized + suspended) because Order.buyerId,
 * Listing.sellerId, Review.reviewerId, and PreOrderCampaign.sellerId are
 * required FKs without ON DELETE CASCADE. Marketplace history stays intact
 * without exposing personal data.
 */
async function deleteAuthenticatedAccount(userId) {
  if (!userId) {
    const err = new Error("Authenticated user is required");
    err.statusCode = 401;
    throw err;
  }

  return prisma.$transaction(async (tx) => {
    const user = await tx.user.findUnique({ where: { id: userId } });
    if (!user) {
      const err = new Error("User not found");
      err.statusCode = 404;
      throw err;
    }
    if (user.suspended && String(user.phone || "").startsWith("deleted_")) {
      return { alreadyDeleted: true, userId };
    }

    await tx.refreshToken.deleteMany({ where: { userId } });
    await tx.deviceToken.deleteMany({ where: { userId } });

    await tx.listing.updateMany({
      where: { sellerId: userId, campaignId: null },
      data: { status: "inactive" },
    });

    await tx.preOrderCampaign.updateMany({
      where: {
        sellerId: userId,
        status: { in: ["draft", "open"] },
      },
      data: { status: "cancelled" },
    });

    await tx.review.updateMany({
      where: { reviewerId: userId },
      data: {
        hidden: true,
        comment: null,
        tags: [],
      },
    });

    await tx.user.update({
      where: { id: userId },
      data: {
        phone: `deleted_${userId}`,
        name: null,
        profilePhotoUrl: null,
        upiId: null,
        upiDisplayName: null,
        paymentEnabled: false,
        role: "buyer",
        sellingReachLevel: "MY_SOCIETY",
        fulfilmentMode: "BUYER_PICKUP",
        deliveryCharge: 0,
        societyId: null,
        flatId: null,
        suspended: true,
      },
    });

    return { alreadyDeleted: false, userId };
  });
}

module.exports = {
  deleteAuthenticatedAccount,
};
