const LISTING_FOOD_CATEGORIES = Object.freeze([
  "Breakfast",
  "Lunch",
  "Dinner",
  "Snacks",
  "Desserts",
]);

const CATEGORY_BY_KEY = Object.freeze(
  Object.fromEntries(
    LISTING_FOOD_CATEGORIES.flatMap((label) => [
      [label.toUpperCase(), label],
      [label, label],
    ])
  )
);

function _badRequest(message) {
  const err = new Error(message);
  err.statusCode = 400;
  return err;
}

function normalizeListingCategory(value) {
  if (value === undefined || value === null) return null;
  const raw = String(value).trim();
  if (!raw) return null;
  if (raw.toUpperCase() === "ALL" || raw.toLowerCase() === "all categories") {
    return null;
  }
  return CATEGORY_BY_KEY[raw] || CATEGORY_BY_KEY[raw.toUpperCase()] || null;
}

function listingCategoriesFromRecord(listing) {
  if (!listing) return [];
  if (Array.isArray(listing.categories) && listing.categories.length > 0) {
    return listing.categories.filter(Boolean).map(String);
  }
  if (listing.category) return [String(listing.category)];
  return [];
}

function categoryWriteFields(categories) {
  const list = Array.isArray(categories) ? categories.filter(Boolean) : [];
  return {
    categories: list,
    category: list[0] || null,
  };
}

function parseListingCategories(input, { required = false } = {}) {
  const hasCategories = input && input.categories !== undefined;
  const hasCategory = input && input.category !== undefined;
  if (!hasCategories && !hasCategory) {
    if (required) {
      throw _badRequest("Please select at least one category.");
    }
    return undefined;
  }

  let raw;
  if (hasCategories) {
    raw = input.categories;
  } else if (input.category == null || input.category === "") {
    raw = [];
  } else {
    raw = [input.category];
  }

  if (!Array.isArray(raw)) {
    throw _badRequest("categories must be an array");
  }

  const unique = [];
  for (const item of raw) {
    const mapped = normalizeListingCategory(item);
    if (!mapped) {
      throw _badRequest(
        "categories must be Breakfast, Lunch, Dinner, Snacks, or Desserts"
      );
    }
    if (!unique.includes(mapped)) unique.push(mapped);
  }

  if (unique.length === 0) {
    throw _badRequest("Please select at least one category.");
  }

  return unique;
}

function categoryQueryFilter(category) {
  if (!category) return {};
  const mapped = normalizeListingCategory(category) || String(category);
  return {
    OR: [{ categories: { has: mapped } }, { category: mapped }],
  };
}

module.exports = {
  LISTING_FOOD_CATEGORIES,
  normalizeListingCategory,
  listingCategoriesFromRecord,
  categoryWriteFields,
  parseListingCategories,
  categoryQueryFilter,
};
