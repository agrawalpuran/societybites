const { serializeListing } = require("../utils/listingSerializer");
const { isFssaiSellingRequirementEnabled } = require("./fssaiRequirement");
const { statusesForSellerIds } = require("./fssaiCompliance");
const { attachListingLikes } = require("./listingLikes");
const { attachPurchasedBefore } = require("./buyerPurchaseHistory");
const prisma = require("./prisma");

const FSSAI_BLOCK_REASON =
  "FSSAI registration must be approved before this seller can receive orders";

async function serializeListingsWithSellerOrderability(listings, options = {}) {
  const list = Array.isArray(listings) ? listings : [];
  const viewerUserId = options.viewerUserId || null;
  try {
    await attachListingLikes(prisma, list, viewerUserId);
  } catch (err) {
    console.error("listing likes unavailable", err && err.message ? err.message : err);
    for (const listing of list) {
      if (listing.likeCount == null) listing.likeCount = 0;
      if (listing.likedByMe == null) listing.likedByMe = false;
    }
  }
  try {
    await attachPurchasedBefore(prisma, list, viewerUserId);
  } catch (err) {
    console.error(
      "purchase history unavailable",
      err && err.message ? err.message : err
    );
    for (const listing of list) {
      if (listing && listing.purchasedBefore == null) {
        listing.purchasedBefore = false;
      }
    }
  }
  const requirement = await isFssaiSellingRequirementEnabled();
  if (!requirement) {
    return list.map((listing) =>
      serializeListing(listing, {
        sellerAcceptingOrders: true,
        sellerOrderBlockReason: null,
        viewerUserId,
      })
    );
  }
  const statuses = await statusesForSellerIds(list.map((listing) => listing.sellerId));
  return list.map((listing) => {
    const approved = statuses[listing.sellerId] === "APPROVED";
    return serializeListing(listing, {
      sellerAcceptingOrders: approved,
      sellerOrderBlockReason: approved ? null : FSSAI_BLOCK_REASON,
      viewerUserId,
    });
  });
}

module.exports = {
  FSSAI_BLOCK_REASON,
  serializeListingsWithSellerOrderability,
};
