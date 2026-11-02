function dishKeyFor(listing) {
  const group = listing && listing.variantGroupId;
  if (group && String(group).trim()) return String(group).trim();
  return listing && listing.id ? String(listing.id) : "";
}

function applyListingLikes(listings, { counts, likedKeys }) {
  const list = Array.isArray(listings) ? listings : [];
  const countMap = counts || new Map();
  const liked = likedKeys || new Set();
  for (const listing of list) {
    const key = dishKeyFor(listing);
    listing.likeCount = countMap.get(key) || 0;
    listing.likedByMe = liked.has(key);
  }
  return list;
}

async function attachListingLikes(prisma, listings, viewerUserId) {
  const list = Array.isArray(listings) ? listings : [];
  const keys = [...new Set(list.map(dishKeyFor).filter(Boolean))];
  if (keys.length === 0) return list;

  const grouped = await prisma.listingLike.groupBy({
    by: ["dishKey"],
    where: { dishKey: { in: keys } },
    _count: { _all: true },
  });
  const counts = new Map(grouped.map((row) => [row.dishKey, row._count._all]));
  const liked = new Set();
  if (viewerUserId) {
    const mine = await prisma.listingLike.findMany({
      where: { userId: viewerUserId, dishKey: { in: keys } },
      select: { dishKey: true },
    });
    for (const row of mine) liked.add(row.dishKey);
  }
  return applyListingLikes(list, { counts, likedKeys: liked });
}

async function toggleListingLike(prisma, { userId, listing }) {
  const dishKey = dishKeyFor(listing);
  const existing = await prisma.listingLike.findUnique({
    where: { userId_dishKey: { userId, dishKey } },
  });
  if (existing) {
    await prisma.listingLike.delete({ where: { id: existing.id } });
  } else {
    await prisma.listingLike.create({
      data: { userId, dishKey, listingId: listing.id },
    });
  }
  const likeCount = await prisma.listingLike.count({ where: { dishKey } });
  return { liked: !existing, likeCount, dishKey };
}

async function listListingLikers(prisma, listing) {
  const rows = await prisma.listingLike.findMany({
    where: { dishKey: dishKeyFor(listing) },
    orderBy: { createdAt: "desc" },
    include: { user: { select: { name: true } } },
  });
  return rows.map((row) => ({
    name: (row.user && row.user.name && String(row.user.name).trim()) || "Neighbor",
  }));
}

module.exports = {
  dishKeyFor,
  applyListingLikes,
  attachListingLikes,
  toggleListingLike,
  listListingLikers,
};
