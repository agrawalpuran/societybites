const {
  parseFoodType,
  inferFoodTypeFromTags,
  assertFoodTypeTagCompatibility,
} = require("../utils/foodType");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function expectThrow(fn, statusCode, snippet) {
  try {
    fn();
    throw new Error("expected an error");
  } catch (err) {
    if (err.message === "expected an error") throw err;
    assert(err.statusCode === statusCode, `status ${err.statusCode} != ${statusCode}`);
    assert(
      String(err.message).includes(snippet),
      `message "${err.message}" did not include "${snippet}"`
    );
  }
}

function main() {
  assert(parseFoodType("VEG", { required: true }) === "VEG", "VEG accepted");
  assert(parseFoodType("NON_VEG") === "NON_VEG", "NON_VEG accepted");
  assert(parseFoodType("non-veg") === "NON_VEG", "non-veg normalizes");
  assert(parseFoodType(null) === null, "null foodType stays null");
  assert(parseFoodType(undefined) === null, "missing foodType stays null");

  expectThrow(() => parseFoodType("EGG", { required: true }), 400, "VEG or NON_VEG");
  expectThrow(() => parseFoodType(null, { required: true }), 400, "required");

  assert(inferFoodTypeFromTags(["Vegetarian"]) === "VEG", "Vegetarian tag");
  assert(inferFoodTypeFromTags(["Veg"]) === "VEG", "Veg tag");
  assert(inferFoodTypeFromTags(["Non-Veg"]) === "NON_VEG", "Non-Veg tag");
  assert(inferFoodTypeFromTags(["Non-Vegetarian"]) === "NON_VEG", "Non-Vegetarian tag");
  assert(
    inferFoodTypeFromTags(["Veg", "Non-Veg"]) === null,
    "contradictory tags stay null"
  );
  assert(inferFoodTypeFromTags(["Spicy", "Biryani"]) === null, "do not infer from names");

  expectThrow(
    () => assertFoodTypeTagCompatibility("VEG", ["Egg"]),
    400,
    "Egg"
  );
  expectThrow(
    () => assertFoodTypeTagCompatibility("NON_VEG", ["Vegan"]),
    400,
    "Vegan"
  );
  assertFoodTypeTagCompatibility("NON_VEG", ["Egg"]);
  assertFoodTypeTagCompatibility("VEG", ["Vegan", "Jain"]);

  console.log("food-type tests passed");
}

main();
