const ORDER_STATUS_TO_STEP = {
  ordered: 0,
  preparing: 1,
  ready: 2,
  completed: 3,
  cancelled: -1,
};

function serializeListing(listing) {
  const seller = listing.seller || {};
  const flat = seller.flat;

  return {
    id: listing.id,
    name: listing.name,
    description: listing.description,
    price: listing.price,
    quantity: listing.quantity,
    availableAt: listing.availableAt,
    pickupLocation: listing.pickupLocation,
    imageUrl: listing.imageUrl,
    status: listing.status,
    societyId: listing.societyId,
    sellerId: listing.sellerId,
    sellerName: seller.name || "Neighbor",
    block: flat ? `Block ${flat.block}` : null,
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
    subtotal: order.subtotal,
    communityFee: order.communityFee,
    total: order.total,
    societyId: order.societyId,
    buyerId: order.buyerId,
    items,
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
  };
}

function serializeReview(review) {
  return {
    id: review.id,
    orderId: review.orderId,
    listingId: review.listingId,
    reviewerId: review.reviewerId,
    name: review.reviewer?.name || "Neighbor",
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
