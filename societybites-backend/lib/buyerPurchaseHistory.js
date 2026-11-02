const COMPLETED_STATUS = "completed";
const MS_PER_DAY = 24 * 60 * 60 * 1000;
const ROLLING_WINDOW_DAYS = 365;

function purchaseWindowStart(now = new Date()) {
  return new Date(now.getTime() - ROLLING_WINDOW_DAYS * MS_PER_DAY);
}

function variantIdentityKey(sellerId, variantGroupId, variantLabel) {
  const seller = String(sellerId || "").trim();
  const group = String(variantGroupId || "").trim();
  const label = String(variantLabel || "").trim();
  if (!seller || !group || !label) return null;
  return `v:${seller}:${group}:${label}`;
}

function addIdentityKeys(target, listing, listingId) {
  if (listingId) target.add(`id:${listingId}`);
  if (!listing) return;
  if (listing.id) target.add(`id:${listing.id}`);
  if (listing.sourceListingId) target.add(`id:${listing.sourceListingId}`);
  const variantKey = variantIdentityKey(
    listing.sellerId,
    listing.variantGroupId,
    listing.variantLabel
  );
  if (variantKey) target.add(variantKey);
}

function listingIdentityKeys(listing) {
  const keys = new Set();
  addIdentityKeys(keys, listing, listing && listing.id);
  return keys;
}

function listingMatchesPurchase(listing, purchasedKeys) {
  if (!listing || !purchasedKeys || purchasedKeys.size === 0) return false;
  for (const key of listingIdentityKeys(listing)) {
    if (purchasedKeys.has(key)) return true;
  }
  return false;
}

async function loadPurchasedIdentityKeys(prisma, buyerId, now = new Date()) {
  if (!buyerId) return new Set();
  const since = purchaseWindowStart(now);
  const items = await prisma.orderItem.findMany({
    where: {
      order: {
        buyerId,
        status: COMPLETED_STATUS,
        OR: [
          { completedAt: { gte: since } },
          {
            AND: [{ completedAt: null }, { pickedUpAt: { gte: since } }],
          },
        ],
      },
    },
    select: {
      listingId: true,
      listing: {
        select: {
          id: true,
          sellerId: true,
          variantGroupId: true,
          variantLabel: true,
          sourceListingId: true,
        },
      },
    },
  });
  const keys = new Set();
  for (const item of items) {
    addIdentityKeys(keys, item.listing, item.listingId);
  }
  return keys;
}

async function attachPurchasedBefore(prisma, listings, buyerId, now = new Date()) {
  const list = Array.isArray(listings) ? listings : [];
  if (list.length === 0) return list;
  if (!buyerId) {
    for (const listing of list) {
      if (listing) listing.purchasedBefore = false;
    }
    return list;
  }
  const purchasedKeys = await loadPurchasedIdentityKeys(prisma, buyerId, now);
  for (const listing of list) {
    if (!listing) continue;
    listing.purchasedBefore = listingMatchesPurchase(listing, purchasedKeys);
  }
  return list;
}

module.exports = {
  COMPLETED_STATUS,
  ROLLING_WINDOW_DAYS,
  purchaseWindowStart,
  variantIdentityKey,
  listingIdentityKeys,
  listingMatchesPurchase,
  loadPurchasedIdentityKeys,
  attachPurchasedBefore,
};
