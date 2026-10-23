/**
 * Admin order drill-down. Includes buyer and seller contact and address.
 * Admin support sees the flat even when the seller hides it from buyers.
 */

const partySelect = {
  id: true,
  name: true,
  phone: true,
  role: true,
  upiId: true,
  upiDisplayName: true,
  fulfilmentMode: true,
  hideFlatNumber: true,
  society: {
    select: {
      id: true,
      name: true,
      city: true,
      address: true,
      state: true,
      pincode: true,
    },
  },
  flat: {
    select: {
      block: true,
      flatNumber: true,
      floor: true,
      unit: true,
    },
  },
};

const adminOrderInclude = {
  buyer: { select: partySelect },
  society: {
    select: {
      id: true,
      name: true,
      city: true,
      address: true,
      state: true,
      pincode: true,
    },
  },
  items: {
    include: {
      listing: {
        select: {
          id: true,
          name: true,
          sellerId: true,
          pickupLocation: true,
          seller: { select: partySelect },
        },
      },
    },
  },
  couponRedemptions: {
    select: {
      status: true,
      discountAmount: true,
      coupon: { select: { code: true, name: true } },
    },
  },
};

function textOrNull(value) {
  if (value == null) return null;
  const text = String(value).trim();
  return text.length ? text : null;
}

function societyFromRow(society) {
  if (!society) return null;
  return {
    id: society.id,
    name: textOrNull(society.name),
    city: textOrNull(society.city),
    address: textOrNull(society.address),
    state: textOrNull(society.state),
    pincode: textOrNull(society.pincode),
  };
}

function flatFromRow(flat) {
  if (!flat) return null;
  return {
    block: textOrNull(flat.block),
    flatNumber: textOrNull(flat.flatNumber),
    floor: flat.floor == null ? null : flat.floor,
    unit: textOrNull(flat.unit),
  };
}

function partyFromUser(user) {
  if (!user) return null;
  return {
    id: user.id,
    name: textOrNull(user.name),
    phone: textOrNull(user.phone),
    role: textOrNull(user.role),
    upiId: textOrNull(user.upiId),
    upiDisplayName: textOrNull(user.upiDisplayName),
    fulfilmentMode: textOrNull(user.fulfilmentMode),
    hideFlatNumber: Boolean(user.hideFlatNumber),
    society: societyFromRow(user.society),
    flat: flatFromRow(user.flat),
  };
}

function activeCoupon(order) {
  const rows = Array.isArray(order.couponRedemptions) ? order.couponRedemptions : [];
  const live =
    rows.find((row) => row.status === "REDEEMED") ||
    rows.find((row) => row.status === "APPLIED");
  if (!live) return null;
  return {
    code: live.coupon?.code || null,
    name: live.coupon?.name || null,
    status: live.status,
    discountAmount: live.discountAmount,
  };
}

function sellersFromItems(items) {
  const byId = new Map();
  for (const item of items || []) {
    const seller = item.listing && item.listing.seller;
    if (!seller || !seller.id || byId.has(seller.id)) continue;
    byId.set(seller.id, partyFromUser(seller));
  }
  return [...byId.values()];
}

function serializeAdminOrder(order) {
  const items = (order.items || []).map((item) => {
    const quantity = Number(item.quantity) || 0;
    const unitPrice = Number(item.unitPrice) || 0;
    const listing = item.listing || null;
    const seller = listing && listing.seller;
    return {
      id: item.id,
      quantity,
      unitPrice,
      lineTotal: quantity * unitPrice,
      listing: listing
        ? {
            id: listing.id,
            name: listing.name || null,
            pickupLocation: listing.pickupLocation || null,
            sellerId: listing.sellerId || seller?.id || null,
            sellerName: seller?.name || null,
          }
        : null,
    };
  });

  return {
    id: order.id,
    orderNumber: order.orderNumber,
    status: order.status,
    type: order.type || "regular",
    paymentMethod: order.paymentMethod,
    paymentStatus: order.paymentStatus || "pending",
    subtotal: order.subtotal,
    communityFee: order.communityFee,
    deliveryCharge: order.deliveryCharge || 0,
    total: order.total,
    coupon: activeCoupon(order),
    fulfilmentMethod: order.fulfilmentMethod || null,
    deliveryCollectBy: order.deliveryCollectBy || null,
    deliveryCashConfirmedAt: order.deliveryCashConfirmedAt || null,
    fulfilmentNotes: textOrNull(order.fulfilmentNotes),
    fulfilmentAt: order.fulfilmentAt || null,
    buyerMarkedPaidAt: order.buyerMarkedPaidAt || null,
    sellerConfirmedPaidAt: order.sellerConfirmedPaidAt || null,
    upiTransactionRef: textOrNull(order.upiTransactionRef),
    cancelReason: textOrNull(order.cancelReason),
    rejectReason: textOrNull(order.rejectReason),
    rejectedAt: order.rejectedAt || null,
    expectedReadyAt: order.expectedReadyAt || null,
    requestedReadyAt: order.requestedReadyAt || null,
    society: societyFromRow(order.society),
    buyer: partyFromUser(order.buyer),
    sellers: sellersFromItems(order.items),
    items,
    timeline: {
      createdAt: order.createdAt,
      acceptedAt: order.acceptedAt || null,
      preparingAt: order.preparingAt || null,
      readyAt: order.readyAt || null,
      pickedUpAt: order.pickedUpAt || null,
      completedAt: order.completedAt || null,
      cancelledAt: order.cancelledAt || null,
    },
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
  };
}

async function getAdminOrderDetail(db, orderId) {
  const order = await db.order.findUnique({
    where: { id: String(orderId) },
    include: adminOrderInclude,
  });
  if (!order) return null;
  return serializeAdminOrder(order);
}

module.exports = {
  adminOrderInclude,
  serializeAdminOrder,
  getAdminOrderDetail,
};
