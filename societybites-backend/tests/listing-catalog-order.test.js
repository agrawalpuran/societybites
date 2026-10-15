require("dotenv").config();
const {
  sortSellerCatalogListings,
  parseOrderedListingIds,
} = require("../lib/listingCatalogOrder");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function main() {
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

  console.log("listing-catalog-order.test.js OK");
}

main();
