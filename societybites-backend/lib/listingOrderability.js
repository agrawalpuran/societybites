const { serializeListing } = require("../utils/listingSerializer");
const { isFssaiSellingRequirementEnabled } = require("./fssaiRequirement");
const { statusesForSellerIds } = require("./fssaiCompliance");

const FSSAI_BLOCK_REASON = "FSSAI registration required";

async function serializeListingsWithSellerOrderability(listings) {
  const list = Array.isArray(listings) ? listings : [];
  const requirement = await isFssaiSellingRequirementEnabled();
  if (!requirement) {
    return list.map((listing) =>
      serializeListing(listing, {
        sellerAcceptingOrders: true,
        sellerOrderBlockReason: null,
      })
    );
  }
  const statuses = await statusesForSellerIds(list.map((listing) => listing.sellerId));
  return list.map((listing) => {
    const approved = statuses[listing.sellerId] === "APPROVED";
    return serializeListing(listing, {
      sellerAcceptingOrders: approved,
      sellerOrderBlockReason: approved ? null : FSSAI_BLOCK_REASON,
    });
  });
}

module.exports = {
  FSSAI_BLOCK_REASON,
  serializeListingsWithSellerOrderability,
};
