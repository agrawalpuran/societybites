const {
  parseVariantCreateRows,
  parseVariantCreatePayload,
  sortVariantSiblings,
  orderableQuantity,
  sharedPoolCost,
  isSharedVariantInventory,
  VARIANT_INVENTORY_SHARED,
  VARIANT_INVENTORY_SEPARATE,
} = require("../lib/listingVariants");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(parseVariantCreateRows(null) === null, "null variants");
assert(parseVariantCreateRows([]) === null, "empty variants");

let threw = false;
try {
  parseVariantCreateRows([{ label: "250 g", price: 80, quantity: 1 }]);
} catch (err) {
  threw = err.statusCode === 400;
}
assert(threw, "single variant rejected");

const rows = parseVariantCreateRows([
  { label: "500 g", price: 150, quantity: 4 },
  { label: "250 g", price: 80, quantity: 10 },
]);
assert(rows.length === 2, "two variants");
assert(rows[0].variantLabel === "500 g", "preserves order");
assert(rows[1].price === 80, "second price");
assert(rows[0].variantInventoryMode === VARIANT_INVENTORY_SEPARATE, "default SEPARATE");

const sorted = sortVariantSiblings([
  { price: 150, variantLabel: "500 g" },
  { price: 80, variantLabel: "250 g" },
]);
assert(sorted[0].variantLabel === "250 g", "sort cheapest first");

const shared = parseVariantCreatePayload({
  variants: [
    { label: "250 g", price: 80, portionUnits: 250 },
    { label: "500 g", price: 150, portionUnits: 500 },
  ],
  variantInventoryMode: "SHARED",
  sharedPoolQuantity: 10000,
});
assert(shared.mode === VARIANT_INVENTORY_SHARED, "SHARED mode");
assert(shared.poolQuantity === 10000, "pool total");
assert(shared.rows[0].quantity === 10000, "siblings store pool qty");
assert(shared.rows[0].portionUnits === 250, "portion units");
assert(shared.rows[1].portionUnits === 500, "second portion");

const converted = parseVariantCreatePayload({
  variants: [
    { price: 80, portionAmount: 250, portionUnit: "grams" },
    { price: 150, portionAmount: 500, portionUnit: "grams" },
  ],
  variantInventoryMode: "SHARED",
  sharedPoolQuantity: 10,
  sharedPoolUnit: "kg",
});
assert(converted.poolQuantity === 10000, "10 kg → 10000 g");
assert(converted.rows[0].portionUnits === 250, "250 g stays 250 base");
assert(converted.rows[1].portionUnits === 500, "500 g stays 500 base");
assert(converted.rows[0].variantLabel.includes("250"), "auto label");

threw = false;
try {
  parseVariantCreatePayload({
    variants: [
      { label: "250 g", price: 80, portionUnits: 250 },
      { label: "2 kg", price: 400, portionUnits: 20000 },
    ],
    variantInventoryMode: "SHARED",
    sharedPoolQuantity: 10000,
  });
} catch (err) {
  threw = err.statusCode === 400;
}
assert(threw, "portion cannot exceed pool");

const listing = {
  quantity: 1000,
  portionUnits: 500,
  variantInventoryMode: VARIANT_INVENTORY_SHARED,
};
assert(isSharedVariantInventory(listing), "shared detect");
assert(orderableQuantity(listing) === 2, "floor pool/portion");
assert(sharedPoolCost(listing, 2) === 1000, "cost for 2x500");
assert(orderableQuantity({ quantity: 7 }) === 7, "SEPARATE orderable");

console.log("listing-variants.test.js passed");
