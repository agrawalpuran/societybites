const FOOD_TYPES = Object.freeze(["VEG", "NON_VEG"]);

function _badRequest(message) {
  const err = new Error(message);
  err.statusCode = 400;
  return err;
}

function parseFoodType(value, { required = false } = {}) {
  if (value === undefined || value === null || String(value).trim() === "") {
    if (required) {
      throw _badRequest("foodType is required and must be VEG or NON_VEG");
    }
    return null;
  }

  const mapped = String(value).trim().toUpperCase().replace(/-/g, "_");
  if (!FOOD_TYPES.includes(mapped)) {
    throw _badRequest("foodType must be VEG or NON_VEG");
  }
  return mapped;
}

function inferFoodTypeFromTags(tags) {
  const list = Array.isArray(tags)
    ? tags.map((tag) => String(tag).trim().toLowerCase())
    : [];
  const hasVeg = list.some((tag) => tag === "vegetarian" || tag === "veg");
  const hasNonVeg = list.some(
    (tag) => tag === "non-vegetarian" || tag === "non-veg" || tag === "non_veg"
  );
  if (hasVeg && hasNonVeg) return null;
  if (hasVeg) return "VEG";
  if (hasNonVeg) return "NON_VEG";
  return null;
}

function assertFoodTypeTagCompatibility(foodType, tags) {
  if (!foodType) return;
  const list = Array.isArray(tags)
    ? tags.map((tag) => String(tag).trim().toLowerCase())
    : [];
  if (list.includes("egg") && foodType !== "NON_VEG") {
    throw _badRequest("Egg listings must be Non-Vegetarian");
  }
  if ((list.includes("vegan") || list.includes("jain")) && foodType !== "VEG") {
    throw _badRequest("Vegan and Jain listings must be Vegetarian");
  }
}

module.exports = {
  FOOD_TYPES,
  parseFoodType,
  inferFoodTypeFromTags,
  assertFoodTypeTagCompatibility,
};
