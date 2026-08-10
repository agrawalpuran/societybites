const ORDER_STATUS_TO_STEP = {
  pending: 0,
  accepted: 1,
  preparing: 2,
  ready: 3,
  picked_up: 4,
  completed: 5,
  cancelled: -1,
  rejected: -1,
};

function serializeListing(listing) {
  const seller = listing.seller || {};
  const flat = seller.flat;
  const reviews = listing.reviews || [];
  const reviewCount = reviews.length;
  const avgRating = reviewCount > 0
    ? reviews.reduce((sum, r) => sum + r.rating, 0) / reviewCount
    : 0;

  return {
    id: listing.id,
    name: listing.name,
    description: listing.description,
    price: listing.price,
    quantity: listing.quantity,
    availableAt: listing.availableAt,
    pickupLocation: listing.pickupLocation,
    imageUrl: listing.imageUrl,
    weightUnit: listing.weightUnit,
    weightValue: listing.weightValue,
    tags: listing.tags || [],
    category: listing.category || null,
    status: listing.status,
    societyId: listing.societyId,
    sellerId: listing.sellerId,
    sellerName: seller.name || "Neighbor",
    sellerUpiId: seller.upiId || null,
    sellerUpiDisplayName: seller.upiDisplayName || null,
    block: flat ? `Block ${flat.block}` : null,
    flatNumber: flat?.flatNumber || null,
    avgRating: Math.round(avgRating * 10) / 10,
    reviewCount,
    createdAt: listing.createdAt,
    updatedAt: listing.updatedAt,
  };
}

function serializeOrder(order) {
  const items = (order.items || []).map((item) => ({
    id: item.id,
    quantity: item.quantity,
    unitPrice: item.unitPrice,
    total: item.quantity * item.unitPrice,
    listing: item.listing ? serializeListing({ ...item.listing, seller: item.listing.seller }) : null,
  }));

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
    societyId: order.societyId,
    buyerId: order.buyerId,
    hasReview: Array.isArray(order.reviews) && order.reviews.length > 0,
    rejectReason: order.rejectReason || null,
    rejectedAt: order.rejectedAt || null,
    rejectedBy: order.rejectedBy || null,
    items,
    timeline: {
      createdAt: order.createdAt,
      acceptedAt: order.acceptedAt || null,
      preparingAt: order.preparingAt || null,
      readyAt: order.readyAt || null,
      pickedUpAt: order.pickedUpAt || null,
      completedAt: order.completedAt || null,
      cancelledAt: order.cancelledAt || null,
      rejectedAt: order.rejectedAt || null,
    },
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
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
  serializeReview,
};
