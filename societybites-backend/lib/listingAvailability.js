const AVAILABILITY_MODES = ["READY_NOW", "MADE_TO_ORDER"];
const ACCEPTED_TODAY_STATUSES = [
  "accepted",
  "preparing",
  "ready",
  "picked_up",
  "completed",
];

function parseAvailabilityMode(
  value,
  { required = false, defaultValue = "READY_NOW" } = {}
) {
  if (value == null || value === "") {
    if (required) {
      const err = new Error("availabilityMode must be READY_NOW or MADE_TO_ORDER");
      err.statusCode = 400;
      throw err;
    }
    return defaultValue;
  }
  const raw = String(value).trim().toUpperCase();
  if (!AVAILABILITY_MODES.includes(raw)) {
    const err = new Error("availabilityMode must be READY_NOW or MADE_TO_ORDER");
    err.statusCode = 400;
    throw err;
  }
  return raw;
}

function parsePreparationTimeMinutes(value, { required = false } = {}) {
  if (value == null || value === "") {
    if (required) {
      const err = new Error(
        "preparationTimeMinutes is required for Made to Order listings"
      );
      err.statusCode = 400;
      throw err;
    }
    return null;
  }
  const n = parseInt(value, 10);
  if (!Number.isFinite(n) || n < 15 || n > 10080) {
    const err = new Error("preparationTimeMinutes must be between 15 and 10080");
    err.statusCode = 400;
    throw err;
  }
  return n;
}

function parseMaxDailyOrders(value) {
  if (value == null || value === "") return null;
  const n = parseInt(value, 10);
  if (!Number.isFinite(n) || n < 1 || n > 999) {
    const err = new Error("maxDailyOrders must be a positive number");
    err.statusCode = 400;
    throw err;
  }
  return n;
}

function isMadeToOrderListing(listing) {
  return Boolean(
    listing &&
      (listing.catalogType || "REGULAR") !== "PREORDER" &&
      listing.availabilityMode === "MADE_TO_ORDER" &&
      !listing.campaignId
  );
}

function assertRegularOrderAvailabilityMix(listings) {
  let hasMadeToOrder = false;
  let hasAvailableNow = false;
  for (const listing of listings || []) {
    if ((listing.catalogType || "REGULAR") === "PREORDER" || listing.campaignId) {
      continue;
    }
    if (isMadeToOrderListing(listing)) hasMadeToOrder = true;
    else hasAvailableNow = true;
  }
  if (hasMadeToOrder && hasAvailableNow) {
    const err = new Error(
      "Cannot mix Available now and Made to order items in one order"
    );
    err.statusCode = 400;
    err.code = "MIXED_AVAILABILITY";
    throw err;
  }
}

const BUYER_VISIBLE_STATUSES = ["active", "sold_out"];
const SINGLE_MADE_TO_ORDER_MESSAGE =
  "Only one Made to order listing can be live at a time. Buyers need a single prep time. Pause or edit your current Made to order item instead.";
const MULTIPLE_MADE_TO_ORDER_CART_MESSAGE =
  "This cart can hold one Made to order item at a time so the ready time stays clear. Checkout this one first, then order the other.";

function singleMadeToOrderError() {
  const err = new Error(SINGLE_MADE_TO_ORDER_MESSAGE);
  err.statusCode = 400;
  err.code = "SINGLE_MADE_TO_ORDER";
  return err;
}

function isBuyerVisibleMadeToOrder(listing) {
  return (
    isMadeToOrderListing(listing) &&
    BUYER_VISIBLE_STATUSES.includes(listing.status || "active")
  );
}

async function assertSingleBuyerVisibleMadeToOrder(
  prisma,
  { sellerId, excludeListingId } = {}
) {
  const existing = await prisma.listing.findFirst({
    where: {
      sellerId,
      campaignId: null,
      catalogType: { not: "PREORDER" },
      availabilityMode: "MADE_TO_ORDER",
      status: { in: BUYER_VISIBLE_STATUSES },
      ...(excludeListingId ? { id: { not: excludeListingId } } : {}),
    },
    select: { id: true },
  });
  if (existing) throw singleMadeToOrderError();
}

function assertSingleMadeToOrderListingInOrder(listings) {
  const ids = new Set();
  for (const listing of listings || []) {
    if (isMadeToOrderListing(listing)) ids.add(listing.id);
  }
  if (ids.size > 1) {
    const err = new Error(MULTIPLE_MADE_TO_ORDER_CART_MESSAGE);
    err.statusCode = 400;
    err.code = "MULTIPLE_MADE_TO_ORDER";
    throw err;
  }
}

function utcStartOfToday() {
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  return start;
}

function availabilityWriteFields({
  catalogType,
  availabilityMode,
  preparationTimeMinutes,
  maxDailyOrders,
} = {}) {
  if ((catalogType || "REGULAR") === "PREORDER") {
    if (
      availabilityMode != null &&
      availabilityMode !== "" &&
      parseAvailabilityMode(availabilityMode) === "MADE_TO_ORDER"
    ) {
      const err = new Error("Pre-order listings cannot be Made to Order");
      err.statusCode = 400;
      throw err;
    }
    return {
      availabilityMode: "READY_NOW",
      preparationTimeMinutes: null,
      maxDailyOrders: null,
    };
  }

  const mode = parseAvailabilityMode(availabilityMode);
  if (mode === "READY_NOW") {
    return {
      availabilityMode: "READY_NOW",
      preparationTimeMinutes: null,
      maxDailyOrders: null,
    };
  }

  return {
    availabilityMode: "MADE_TO_ORDER",
    preparationTimeMinutes: parsePreparationTimeMinutes(preparationTimeMinutes, {
      required: true,
    }),
    maxDailyOrders: parseMaxDailyOrders(maxDailyOrders),
  };
}

function availabilityUpdateFields(body, listing) {
  const hasMode = body.availabilityMode !== undefined;
  const hasPrep = body.preparationTimeMinutes !== undefined;
  const hasMax = body.maxDailyOrders !== undefined;
  if (!hasMode && !hasPrep && !hasMax) return undefined;

  return availabilityWriteFields({
    catalogType: listing.catalogType,
    availabilityMode: hasMode ? body.availabilityMode : listing.availabilityMode,
    preparationTimeMinutes: hasPrep
      ? body.preparationTimeMinutes
      : listing.preparationTimeMinutes,
    maxDailyOrders: hasMax ? body.maxDailyOrders : listing.maxDailyOrders,
  });
}

async function countAcceptedMadeToOrderToday(prisma, listingId) {
  return prisma.orderItem.count({
    where: {
      listingId,
      order: {
        acceptedAt: { gte: utcStartOfToday() },
        status: { in: ACCEPTED_TODAY_STATUSES },
      },
    },
  });
}

async function assertMadeToOrderCapacity(prisma, listing) {
  if (!isMadeToOrderListing(listing)) return;
  if (listing.maxDailyOrders == null) return;
  const count = await countAcceptedMadeToOrderToday(prisma, listing.id);
  if (count >= listing.maxDailyOrders) {
    const err = new Error(`"${listing.name}" is currently unavailable`);
    err.statusCode = 400;
    err.code = "MADE_TO_ORDER_CAPACITY";
    throw err;
  }
}

async function attachMadeToOrderCapacity(prisma, listings) {
  const limited = (listings || []).filter(
    (listing) =>
      isMadeToOrderListing(listing) && listing.maxDailyOrders != null
  );
  if (!limited.length) {
    return listings;
  }

  const grouped = await prisma.orderItem.groupBy({
    by: ["listingId"],
    where: {
      listingId: { in: limited.map((listing) => listing.id) },
      order: {
        acceptedAt: { gte: utcStartOfToday() },
        status: { in: ACCEPTED_TODAY_STATUSES },
      },
    },
    _count: { _all: true },
  });
  const usedByListing = Object.fromEntries(
    grouped.map((row) => [row.listingId, row._count._all])
  );

  return listings.map((listing) => {
    if (!isMadeToOrderListing(listing) || listing.maxDailyOrders == null) {
      return listing;
    }
    const used = usedByListing[listing.id] || 0;
    return {
      ...listing,
      madeToOrderUnavailableToday: used >= listing.maxDailyOrders,
    };
  });
}

module.exports = {
  AVAILABILITY_MODES,
  parseAvailabilityMode,
  parsePreparationTimeMinutes,
  parseMaxDailyOrders,
  isMadeToOrderListing,
  assertRegularOrderAvailabilityMix,
  assertSingleBuyerVisibleMadeToOrder,
  assertSingleMadeToOrderListingInOrder,
  isBuyerVisibleMadeToOrder,
  SINGLE_MADE_TO_ORDER_MESSAGE,
  MULTIPLE_MADE_TO_ORDER_CART_MESSAGE,
  availabilityWriteFields,
  availabilityUpdateFields,
  countAcceptedMadeToOrderToday,
  assertMadeToOrderCapacity,
  attachMadeToOrderCapacity,
};
