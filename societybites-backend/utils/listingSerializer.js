const { distanceKmBetweenCoordinates } = require("../lib/geoDistance");
const { listingCategoriesFromRecord } = require("./listingCategories");
const { serializePaymentPreference } = require("../lib/sellerPaymentPreference");
const { serializeFulfilment } = require("../lib/sellerFulfilment");
const { evaluateRecurringAvailability } = require("../lib/recurringAvailability");
const { sellerCanDecline } = require("../lib/orderAcceptance");

const ORDER_ENDED_WITHOUT_FOOD = new Set(["rejected", "cancelled"]);

/**
 * The platform never holds money, so a refund is a transfer the seller owes the
 * buyer directly. Surfacing it keeps both sides looking at the same number.
 */
function isRefundDue(order) {
  if (!ORDER_ENDED_WITHOUT_FOOD.has(order.status)) return false;
  if (String(order.paymentMethod || "upi").toLowerCase() !== "upi") return false;
  return Boolean(order.buyerMarkedPaidAt || order.sellerConfirmedPaidAt);
}

const ORDER_STATUS_TO_STEP = {
  pending: 0,
  accepted: 1,
  preparing: 1,
  ready: 2,
  picked_up: 2,
  completed: 3,
  cancelled: -1,
  rejected: -1,
};

function serializeListing(listing, options = {}) {
  const sellerAcceptingOrders = options.sellerAcceptingOrders !== false;
  const sellerOrderBlockReason =
    options.sellerOrderBlockReason != null ? options.sellerOrderBlockReason : null;
  const seller = listing.seller || {};
  const flat = seller.flat;
  const fulfilment = serializeFulfilment(seller);
  let reviewCount;
  let avgRating;
  if (listing.reviewStats) {
    reviewCount = listing.reviewStats.reviewCount;
    avgRating = listing.reviewStats.avgRating;
  } else {
    const reviews = listing.reviews || [];
    reviewCount = reviews.length;
    avgRating = reviewCount > 0
      ? reviews.reduce((sum, r) => sum + r.rating, 0) / reviewCount
      : 0;
  }
  const recurring = evaluateRecurringAvailability(listing, {
    soldToday: listing.recurringSoldToday || 0,
  });

  return {
    id: listing.id,
    name: listing.name,
    description: listing.description,
    price: listing.price,
    quantity: listing.quantity,
    availableAt: listing.availableAt,
    pickupLocation: listing.pickupLocation,
    imageUrl: listing.imageUrl,
    campaignId: listing.campaignId || null,
    inventoryMode: listing.inventoryMode || null,
    weightUnit: listing.weightUnit,
    weightValue: listing.weightValue,
    tags: listing.tags || [],
    foodType: listing.foodType || null,
    category: listingCategoriesFromRecord(listing)[0] || listing.category || null,
    categories: listingCategoriesFromRecord(listing),
    status: listing.status,
    catalogType: listing.catalogType || "REGULAR",
    availabilityMode: listing.availabilityMode || "READY_NOW",
    preparationTimeMinutes:
      listing.preparationTimeMinutes == null
        ? null
        : listing.preparationTimeMinutes,
    maxDailyOrders: listing.maxDailyOrders == null ? null : listing.maxDailyOrders,
    madeToOrderUnavailableToday: Boolean(listing.madeToOrderUnavailableToday),
    recurringEnabled: recurring.recurringEnabled,
    recurringWeekdays: Array.isArray(listing.recurringWeekdays)
      ? listing.recurringWeekdays
      : [],
    recurringStartMinute:
      listing.recurringStartMinute == null ? null : listing.recurringStartMinute,
    recurringEndMinute:
      listing.recurringEndMinute == null ? null : listing.recurringEndMinute,
    recurringDailyLimit:
      listing.recurringDailyLimit == null ? null : listing.recurringDailyLimit,
    recurringUnavailable: recurring.recurringUnavailable,
    recurringSoldOutToday: recurring.recurringSoldOutToday,
    recurringBuyerLabel: recurring.recurringBuyerLabel,
    recurringNextLabel: recurring.recurringNextLabel,
    recurringScheduleSummary: recurring.recurringScheduleSummary,
    recurringHoursSummary: recurring.recurringHoursSummary,
    recurringDailyLimitLabel: recurring.recurringDailyLimitLabel,
    societyId: listing.societyId,
    sellerId: listing.sellerId,
    sellerName: seller.name || "Neighbor",
    sellerProfilePhotoUrl:
      listing.sellerProfilePhotoUrl || seller.profilePhotoUrl || null,
    sellerUpiId: seller.upiId || null,
    sellerUpiDisplayName: seller.upiDisplayName || null,
    sellerPaymentPreference: serializePaymentPreference(seller),
    kitchenOpensAt: seller.kitchenOpensAt || null,
    kitchenClosesAt: seller.kitchenClosesAt || null,
    fulfilment,
    fulfilmentMode: fulfilment.mode,
    deliveryCharge: fulfilment.deliveryCharge,
    block: flat ? `Block ${flat.block}` : null,
    flatNumber: flat?.flatNumber || null,
    avgRating: Math.round(avgRating * 10) / 10,
    reviewCount,
    quantitySold: Number(listing.quantitySold) || 0,
    sellerAcceptingOrders,
    sellerOrderBlockReason,
    createdAt: listing.createdAt,
    updatedAt: listing.updatedAt,
  };
}

/** Cumulative completed OrderItem quantities. Does not change listing.quantity. */
async function attachQuantitySold(prisma, listings) {
  const list = Array.isArray(listings) ? listings : [];
  const ids = [...new Set(list.map((listing) => listing && listing.id).filter(Boolean))];
  if (ids.length === 0) return list;

  const groups = await prisma.orderItem.groupBy({
    by: ["listingId"],
    where: {
      listingId: { in: ids },
      order: { status: "completed" },
    },
    _sum: { quantity: true },
  });
  const soldByListing = Object.fromEntries(
    groups.map((row) => [row.listingId, Number(row._sum && row._sum.quantity) || 0])
  );
  for (const listing of list) {
    if (listing && listing.id) {
      listing.quantitySold = soldByListing[listing.id] || 0;
    }
  }
  return list;
}

/**
 * Batched review count + average rating for catalog listing reads.
 * Matches serializeListing's in-memory reduce over listing.reviews (all rows, including hidden).
 */
async function attachListingReviewAggregates(prisma, listings) {
  const list = Array.isArray(listings) ? listings : [];
  const ids = [...new Set(list.map((listing) => listing && listing.id).filter(Boolean))];
  if (ids.length === 0) return list;

  const groups = await prisma.review.groupBy({
    by: ["listingId"],
    where: { listingId: { in: ids } },
    _count: { _all: true },
    _avg: { rating: true },
  });
  const statsByListing = Object.fromEntries(
    groups.map((row) => {
      const reviewCount = row._count._all;
      const avg =
        reviewCount > 0 && row._avg.rating != null ? row._avg.rating : 0;
      return [row.listingId, { reviewCount, avgRating: avg }];
    })
  );
  for (const listing of list) {
    if (!listing || !listing.id) continue;
    listing.reviewStats = statsByListing[listing.id] || {
      reviewCount: 0,
      avgRating: 0,
    };
  }
  return list;
}

function roundKm(value) {
  if (!Number.isFinite(value)) return null;
  return Math.round(value * 10) / 10;
}

function serializeOrder(order) {
  const items = (order.items || []).map((item) => ({
    id: item.id,
    quantity: item.quantity,
    unitPrice: item.unitPrice,
    total: item.quantity * item.unitPrice,
    listing: item.listing ? serializeListing({ ...item.listing, seller: item.listing.seller }) : null,
  }));

  const buyer = order.buyer || {};
  const buyerFlat = buyer.flat || null;
  const buyerSociety = buyer.society || null;
  const sellerSociety =
    order.items &&
    order.items[0] &&
    order.items[0].listing &&
    order.items[0].listing.seller &&
    order.items[0].listing.seller.society;
  const distanceKm = roundKm(
    distanceKmBetweenCoordinates(buyerSociety, sellerSociety)
  );

  const activeCoupon = Array.isArray(order.couponRedemptions)
    ? order.couponRedemptions[0]
    : null;

  return {
    id: order.id,
    orderId: order.orderNumber,
    orderNumber: order.orderNumber,
    status: order.status,
    statusStep: ORDER_STATUS_TO_STEP[order.status] ?? 0,
    paymentMethod: order.paymentMethod,
    paymentStatus: order.paymentStatus || "pending",
    buyerMarkedPaidAt: order.buyerMarkedPaidAt || null,
    sellerConfirmedPaidAt: order.sellerConfirmedPaidAt || null,
    upiTransactionRef: order.upiTransactionRef || null,
    subtotal: order.subtotal,
    communityFee: order.communityFee,
    platformFee: order.communityFee,
    total: order.total,
    couponCode: activeCoupon?.coupon?.code || null,
    couponDiscount: activeCoupon ? activeCoupon.discountAmount : null,
    societyEatsSubsidy: activeCoupon ? activeCoupon.discountAmount : null,
    sellerGrossAmount: order.subtotal,
    societyId: order.societyId,
    buyerId: order.buyerId,
    buyerName: buyer.name || null,
    buyerPhone: buyer.phone || null,
    buyerFlatNumber: buyerFlat?.flatNumber || null,
    buyerBlock: buyerFlat?.block || null,
    buyerSocietyName: buyerSociety?.name || null,
    sellerName: items[0]?.listing?.sellerName || null,
    sellerSocietyName: (sellerSociety && sellerSociety.name) || null,
    distanceKm,
    isCrossSociety: Boolean(
      items[0] &&
        items[0].listing &&
        items[0].listing.societyId &&
        order.societyId &&
        items[0].listing.societyId !== order.societyId
    ),
    hasReview: Array.isArray(order.reviews) && order.reviews.length > 0,
    rejectReason: order.rejectReason || null,
    rejectedAt: order.rejectedAt || null,
    rejectedBy: order.rejectedBy || null,
    cancelReason: order.cancelReason || null,
    refundDue: isRefundDue(order),
    sellerCanDecline: sellerCanDecline(order),
    completedAt: order.completedAt || null,
    cancelledAt: order.cancelledAt || null,
    expectedReadyAt: order.expectedReadyAt || null,
    requestedReadyAt: order.requestedReadyAt || null,
    type: order.type || "regular",
    campaignId: order.campaignId || null,
    fulfilmentMethod: order.fulfilmentMethod || null,
    deliveryCharge: order.deliveryCharge || 0,
    fulfilmentNotes: order.fulfilmentNotes || null,
    fulfilmentAt: order.fulfilmentAt || null,
    items,
    timeline: {
      createdAt: order.createdAt,
      acceptedAt: order.acceptedAt || null,
      preparingAt: order.preparingAt || null,
      readyAt: order.readyAt || null,
      expectedReadyAt: order.expectedReadyAt || null,
      pickedUpAt: order.pickedUpAt || null,
      completedAt: order.completedAt || null,
      cancelledAt: order.cancelledAt || null,
      rejectedAt: order.rejectedAt || null,
    },
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
  };
}

/** Small PATCH /orders/:id/status payload — client merges onto the cached order. */
function serializeOrderStatusPatch(order) {
  return {
    statusPatch: true,
    id: order.id,
    orderId: order.orderNumber,
    orderNumber: order.orderNumber,
    status: order.status,
    statusStep: ORDER_STATUS_TO_STEP[order.status] ?? 0,
    paymentStatus: order.paymentStatus || "pending",
    refundDue: isRefundDue(order),
    sellerCanDecline: sellerCanDecline(order),
    completedAt: order.completedAt || null,
    cancelledAt: order.cancelledAt || null,
    rejectedAt: order.rejectedAt || null,
    acceptedAt: order.acceptedAt || null,
    preparingAt: order.preparingAt || null,
    readyAt: order.readyAt || null,
    pickedUpAt: order.pickedUpAt || null,
    expectedReadyAt: order.expectedReadyAt || null,
    sellerConfirmedPaidAt: order.sellerConfirmedPaidAt || null,
    buyerMarkedPaidAt: order.buyerMarkedPaidAt || null,
    cancelReason: order.cancelReason || null,
  };
}

function serializeReview(review) {
  const reviewer = review.reviewer || {};
  const flat = reviewer.flat;
  const listing = review.listing || {};

  return {
    id: review.id,
    orderId: review.orderId,
    listingId: review.listingId,
    listingName: listing.name || null,
    reviewerId: review.reviewerId,
    name: reviewer.name || "Neighbor",
    flatNumber: flat?.flatNumber || null,
    block: flat?.block || null,
    rating: review.rating,
    comment: review.comment,
    tags: review.tags,
    wouldOrderAgain: review.wouldOrderAgain,
    createdAt: review.createdAt,
  };
}

module.exports = {
  ORDER_STATUS_TO_STEP,
  serializeListing,
  serializeOrder,
  serializeOrderStatusPatch,
  serializeReview,
  attachQuantitySold,
  attachListingReviewAggregates,
};
