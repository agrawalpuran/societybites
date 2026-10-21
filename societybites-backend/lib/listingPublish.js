/**
 * Resolve create-time visibility. Default is draft so sellers can build a
 * catalog before going live. Pass publish: true to create as active (tests /
 * explicit publish-now).
 */
function resolveCreateListingStatus(body) {
  if (body && body.publish === true) return "active";
  return "draft";
}

/**
 * Collect draft listing ids to activate: this row, plus draft siblings in the
 * same variant group.
 */
async function draftIdsToPublish(prisma, listing) {
  if (!listing || listing.status !== "draft") return [];
  if (!listing.variantGroupId) return [listing.id];

  const siblings = await prisma.listing.findMany({
    where: {
      variantGroupId: listing.variantGroupId,
      sellerId: listing.sellerId,
      status: "draft",
    },
    select: { id: true },
  });
  return siblings.map((row) => row.id);
}

module.exports = {
  resolveCreateListingStatus,
  draftIdsToPublish,
};
