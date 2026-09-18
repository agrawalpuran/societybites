const {
  parseListingCategories,
  categoryWriteFields,
  categoryQueryFilter,
  listingCategoriesFromRecord,
} = require("../utils/listingCategories");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function expectThrow(fn, snippet) {
  try {
    fn();
    throw new Error("expected throw");
  } catch (err) {
    if (err.message === "expected throw") throw err;
    assert(err.statusCode === 400, `status ${err.statusCode}`);
    assert(String(err.message).includes(snippet), err.message);
  }
}

function main() {
  const one = parseListingCategories({ category: "BREAKFAST" }, { required: true });
  assert(JSON.stringify(one) === JSON.stringify(["Breakfast"]), "single BREAKFAST");
  assert(categoryWriteFields(one).category === "Breakfast", "legacy category first");

  const many = parseListingCategories(
    { categories: ["Breakfast", "LUNCH"] },
    { required: true }
  );
  assert(many.length === 2 && many[1] === "Lunch", "multi categories");

  expectThrow(
    () => parseListingCategories({ categories: [] }, { required: true }),
    "at least one category"
  );
  expectThrow(
    () => parseListingCategories({}, { required: true }),
    "at least one category"
  );
  expectThrow(
    () => parseListingCategories({ categories: ["ALL"] }, { required: true }),
    "Breakfast"
  );
  expectThrow(
    () => parseListingCategories({ categories: ["Pizza"] }, { required: true }),
    "Breakfast"
  );

  const filter = categoryQueryFilter("lunch");
  assert(filter.OR[0].categories.has === "Lunch", "query uses has Lunch");

  const fromOld = listingCategoriesFromRecord({ category: "Dinner", categories: [] });
  assert(fromOld[0] === "Dinner", "legacy record");

  console.log("listing-categories.test.js: PASS");
}

main();
