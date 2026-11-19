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
 * Publication time for an explicit publish-now create. Draft creates omit it.
 * The caller passes a server clock value and writes it in the create statement.
 */
function withCreatePublication(data, status, now = new Date()) {
  if (status !== "active") return { ...data };
  return { ...data, firstPublishedAt: now };
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

/**
 * Activates the given draft ids. A row receives firstPublishedAt only when that
 * column is still null, and only in this same transaction.
 */
async function publishDraftListings(prisma, { sellerId, ids, now = new Date() }) {
  const listingIds = Array.isArray(ids) ? ids.filter(Boolean) : [];
  if (!listingIds.length) return { stamped: [], publishedCount: 0 };
  return prisma.$transaction(async (tx) => {
    const fresh = await tx.listing.findMany({
      where: { id: { in: listingIds }, sellerId, status: "draft", firstPublishedAt: null },
      select: { id: true, sellerId: true },
    });
    const freshIds = fresh.map((row) => row.id);
    let stampedCount = 0;
    if (freshIds.length) {
      const stampedUpdate = await tx.listing.updateMany({
        where: { id: { in: freshIds }, sellerId, status: "draft", firstPublishedAt: null },
        data: { status: "active", firstPublishedAt: now },
      });
      stampedCount = stampedUpdate.count;
    }
    const rest = await tx.listing.updateMany({
      where: { id: { in: listingIds }, sellerId, status: "draft" },
      data: { status: "active" },
    });
    const stamped = freshIds.length
      ? await tx.listing.findMany({
          where: { id: { in: freshIds }, firstPublishedAt: { not: null } },
          select: { id: true, sellerId: true, firstPublishedAt: true },
        })
      : [];
    return { stamped, publishedCount: stampedCount + rest.count };
  });
}

module.exports = {
  resolveCreateListingStatus,
  withCreatePublication,
  draftIdsToPublish,
  publishDraftListings,
};
