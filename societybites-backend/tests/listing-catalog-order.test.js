require("dotenv").config();
const {
  sortSellerCatalogListings,
  parseOrderedListingIds,
  allocateFrontDisplayOrders,
} = require("../lib/listingCatalogOrder");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function main() {
  const items = sortSellerCatalogListings([
    { id: "c", displayOrder: 2, createdAt: new Date("2024-01-01") },
    { id: "a", displayOrder: 0, createdAt: new Date("2024-01-03") },
    { id: "b", displayOrder: 1, createdAt: new Date("2024-01-02") },
    { id: "legacy", displayOrder: null, createdAt: new Date("2024-06-01") },
  ]);
  assert(items.map((row) => row.id).join(",") === "a,b,c,legacy", "displayOrder sort");

  const legacyOnly = sortSellerCatalogListings([
    { id: "old", displayOrder: null, createdAt: new Date("2024-01-01") },
    { id: "new", displayOrder: null, createdAt: new Date("2024-06-01") },
  ]);
  assert(legacyOnly[0].id === "new", "legacy fallback is createdAt desc");

  const ids = parseOrderedListingIds({ orderedListingIds: ["a", "b"] });
  assert(ids.length === 2, "parse ids");

  try {
    parseOrderedListingIds({ orderedListingIds: ["a", "a"] });
    throw new Error("expected duplicate reject");
  } catch (err) {
    if (err.message === "expected duplicate reject") throw err;
    assert(/duplicate/i.test(err.message), "duplicate error");
  }

  const calls = [];
  const prisma = {
    listing: {
      updateMany: async (args) => {
        calls.push(args);
        return { count: 2 };
      },
    },
  };
  const start = await allocateFrontDisplayOrders(prisma, "seller-1", 3);
  assert(start === 0, "new listings start at the front");
  assert(calls.length === 1, "existing orders are shifted once");
  assert(calls[0].where.sellerId === "seller-1", "shift is seller-scoped");
  assert(calls[0].data.displayOrder.increment === 3, "shift by SKU count");

  const created = [
    { id: "new", displayOrder: 0 },
    { id: "old-a", displayOrder: 1 },
    { id: "old-b", displayOrder: 2 },
  ];
  assert(
    sortSellerCatalogListings(created).map((row) => row.id).join(",") ===
      "new,old-a,old-b",
    "prepended listing sorts first"
  );

  console.log("listing-catalog-order.test.js OK");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
