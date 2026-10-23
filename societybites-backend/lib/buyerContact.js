const prisma = require("./prisma");

const REVEAL_ACTION = "REVEAL_BUYER_CONTACT";
const MAX_REVEALS_PER_ORDER = 8;
const MAX_NEW_ORDERS_PER_SELLER_DAY = 30;

function kitchenSellerIdFromOrder(order) {
  const first = order && order.items && order.items[0];
  const listing = first && first.listing;
  return (listing && (listing.sellerId || (listing.seller && listing.seller.id))) || null;
}

function maskBuyerPhone(phone) {
  const raw = String(phone || "").trim();
  if (!raw) return null;
  const keep = Math.max(raw.length - 5, 3);
  return `${raw.slice(0, keep)}•••••`;
}

function isSellerDelivery(order) {
  return String((order && order.fulfilmentMethod) || "").trim() === "seller_delivery";
}

function foodPaymentConfirmed(order) {
  const status = (order && order.paymentStatus) || "pending";
  return status === "seller_confirmed" || status === "paid";
}

function isCashOrder(order) {
  return String((order && order.paymentMethod) || "").toLowerCase() === "cash";
}

function canRevealBuyerContact(order) {
  if (!order || !isSellerDelivery(order)) return false;
  const status = order.status;
  if (status === "pending" || status === "cancelled" || status === "rejected") {
    return false;
  }
  if (status !== "accepted" && status !== "ready" && status !== "completed") {
    return false;
  }
  if (isCashOrder(order)) return true;
  return foodPaymentConfirmed(order);
}

function viewerIsKitchenSeller(order, viewerUserId) {
  if (!viewerUserId) return false;
  const sellerId = kitchenSellerIdFromOrder(order);
  return Boolean(sellerId && sellerId === viewerUserId);
}

function serializeBuyerContactForViewer(order, viewerUserId) {
  const raw = (order && order.buyer && order.buyer.phone) || null;
  const kitchenSeller = viewerIsKitchenSeller(order, viewerUserId);
  const allowed = kitchenSeller && canRevealBuyerContact(order);
  return {
    buyerPhone: null,
    buyerPhoneMasked: kitchenSeller ? maskBuyerPhone(raw) : null,
    canRevealBuyerPhone: allowed,
  };
}

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

async function revealBuyerContact({ order, sellerId, acknowledged }) {
  if (!order) {
    throw httpError(404, "Order not found");
  }
  const isSeller = (order.items || []).some(
    (item) => item.listing && item.listing.sellerId === sellerId
  );
  if (!isSeller) {
    throw httpError(403, "Not allowed");
  }
  if (!canRevealBuyerContact(order)) {
    throw httpError(
      400,
      "Buyer number is available after the order is accepted and paid."
    );
  }
  const phone = (order.buyer && order.buyer.phone) || "";
  if (!phone) {
    throw httpError(400, "Buyer number is not available for this order.");
  }

  const existing = await prisma.auditLog.findFirst({
    where: {
      adminId: sellerId,
      action: REVEAL_ACTION,
      target: order.id,
    },
    orderBy: { createdAt: "desc" },
  });
  if (existing) {
    return {
      buyerPhone: phone,
      buyerPhoneMasked: maskBuyerPhone(phone),
    };
  }

  if (acknowledged !== true) {
    throw httpError(400, "Please confirm you will use this number only for this order.");
  }

  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const [orderCount, sellerCount] = await Promise.all([
    prisma.auditLog.count({
      where: {
        action: REVEAL_ACTION,
        target: order.id,
      },
    }),
    prisma.auditLog.count({
      where: {
        adminId: sellerId,
        action: REVEAL_ACTION,
        createdAt: { gte: dayAgo },
      },
    }),
  ]);
  if (orderCount >= MAX_REVEALS_PER_ORDER) {
    throw httpError(429, "Too many attempts to view this number. Try again later.");
  }
  if (sellerCount >= MAX_NEW_ORDERS_PER_SELLER_DAY) {
    throw httpError(429, "Too many number views today. Try again tomorrow.");
  }

  await prisma.auditLog.create({
    data: {
      adminId: sellerId,
      action: REVEAL_ACTION,
      target: order.id,
      details: "acknowledged",
    },
  });

  return {
    buyerPhone: phone,
    buyerPhoneMasked: maskBuyerPhone(phone),
  };
}

module.exports = {
  REVEAL_ACTION,
  canRevealBuyerContact,
  maskBuyerPhone,
  serializeBuyerContactForViewer,
  revealBuyerContact,
  viewerIsKitchenSeller,
};
