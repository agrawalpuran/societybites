/**
 * Lazy listing expiry (no cron): mark past availableAt listings as expired
 * whenever listings are queried or orders are placed.
 */

const EXPIREABLE_STATUSES = ["active", "paused", "sold_out"];

/**
 * Persist status=expired for due listings matching optional filters.
 * @returns {Promise<number>} number of rows updated
 */
async function expireDueListings(prisma, { societyId, sellerId, ids } = {}) {
  const now = new Date();
  const result = await prisma.listing.updateMany({
    where: {
      availableAt: { not: null, lt: now },
      status: { in: EXPIREABLE_STATUSES },
      campaignId: null,
      ...(societyId && { societyId: String(societyId) }),
      ...(sellerId && { sellerId: String(sellerId) }),
      ...(ids && ids.length > 0 && { id: { in: ids } }),
    },
    data: { status: "expired" },
  });
  return result.count;
}

/**
 * If a single listing is past availableAt, persist expired and return updated row.
 */
async function expireListingIfDue(prisma, listing, { include } = {}) {
  if (!listing || !listing.availableAt) return listing;
  if (listing.campaignId) return listing;
  if (!EXPIREABLE_STATUSES.includes(listing.status)) return listing;
  if (new Date(listing.availableAt) >= new Date()) return listing;

  return prisma.listing.update({
    where: { id: listing.id },
    data: { status: "expired" },
    ...(include && { include }),
  });
}

function isPastAvailableAt(listing, now = new Date()) {
  return Boolean(listing?.availableAt && new Date(listing.availableAt) < now);
}

module.exports = {
  EXPIREABLE_STATUSES,
  expireDueListings,
  expireListingIfDue,
  isPastAvailableAt,
};
