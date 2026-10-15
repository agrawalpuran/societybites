const REORDERABLE_CATALOG_WHERE = {
  catalogType: "REGULAR",
  campaignId: null,
  status: { in: ["active", "paused", "sold_out", "expired"] },
};

function sortSellerCatalogListings(listings) {
  const list = Array.isArray(listings) ? [...listings] : [];
  list.sort((a, b) => {
    const ao = a && a.displayOrder;
    const bo = b && b.displayOrder;
    const aHas = ao != null && Number.isFinite(ao);
    const bHas = bo != null && Number.isFinite(bo);
    if (aHas && bHas && ao !== bo) return ao - bo;
    if (aHas !== bHas) return aHas ? -1 : 1;
    const aCreated = a && a.createdAt ? new Date(a.createdAt).getTime() : 0;
    const bCreated = b && b.createdAt ? new Date(b.createdAt).getTime() : 0;
    return bCreated - aCreated;
  });
  return list;
}

function parseOrderedListingIds(body) {
  const raw = body && body.orderedListingIds;
  if (!Array.isArray(raw) || raw.length === 0) {
    const err = new Error("orderedListingIds must be a non-empty array");
    err.statusCode = 400;
    throw err;
  }
  const ids = raw.map((id) => String(id).trim()).filter(Boolean);
  if (ids.length !== raw.length) {
    const err = new Error("orderedListingIds must contain valid listing ids");
    err.statusCode = 400;
    throw err;
  }
  const unique = new Set(ids);
  if (unique.size !== ids.length) {
    const err = new Error("orderedListingIds must not contain duplicates");
    err.statusCode = 400;
    throw err;
  }
  return ids;
}

async function nextDisplayOrderForSeller(prisma, sellerId) {
  const row = await prisma.listing.findFirst({
    where: {
      sellerId: String(sellerId),
      catalogType: "REGULAR",
      campaignId: null,
      displayOrder: { not: null },
    },
    orderBy: { displayOrder: "desc" },
    select: { displayOrder: true },
  });
  const max = row && row.displayOrder != null ? row.displayOrder : -1;
  return max + 1;
}

async function loadReorderableListingIds(prisma, sellerId) {
  const rows = await prisma.listing.findMany({
    where: {
      sellerId: String(sellerId),
      ...REORDERABLE_CATALOG_WHERE,
    },
    select: { id: true },
    orderBy: [{ displayOrder: "asc" }, { createdAt: "desc" }],
  });
  return rows.map((row) => row.id);
}

async function applySellerCatalogOrder(prisma, sellerId, orderedListingIds) {
  const ids = parseOrderedListingIds({ orderedListingIds });
  const expected = await loadReorderableListingIds(prisma, sellerId);
  if (expected.length !== ids.length) {
    const err = new Error(
      "orderedListingIds must include every regular catalog listing for this seller"
    );
    err.statusCode = 400;
    throw err;
  }
  const expectedSet = new Set(expected);
  for (const id of ids) {
    if (!expectedSet.has(id)) {
      const err = new Error("One or more listings are invalid or not yours");
      err.statusCode = 400;
      throw err;
    }
  }

  await prisma.$transaction(
    ids.map((id, index) =>
      prisma.listing.update({
        where: { id },
        data: { displayOrder: index },
      })
    )
  );

  return ids;
}

module.exports = {
  REORDERABLE_CATALOG_WHERE,
  sortSellerCatalogListings,
  parseOrderedListingIds,
  nextDisplayOrderForSeller,
  loadReorderableListingIds,
  applySellerCatalogOrder,
};
