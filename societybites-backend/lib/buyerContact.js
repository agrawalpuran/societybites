const prisma = require("./prisma");

const REVEAL_ACTION = "REVEAL_BUYER_CONTACT";
const REVEAL_SELLER_ACTION = "REVEAL_SELLER_CONTACT";
const MAX_REVEALS_PER_ORDER = 8;
const MAX_NEW_ORDERS_PER_SELLER_DAY = 30;

function kitchenSellerIdFromOrder(order) {
  const first = order && order.items && order.items[0];
  const listing = first && first.listing;
  return (listing && (listing.sellerId || (listing.seller && listing.seller.id))) || null;
}

function sellerPhoneFromOrder(order) {
  const first = order && order.items && order.items[0];
  const listing = first && first.listing;
  const seller = listing && listing.seller;
  const raw = seller && seller.phone;
  return raw ? String(raw).trim() : "";
}

function maskBuyerPhone(phone) {
  const raw = String(phone || "").trim();
  if (!raw) return null;
  const keep = Math.max(raw.length - 5, 3);
  return `${raw.slice(0, keep)}•••••`;
}

function foodPaymentConfirmed(order) {
  const status = (order && order.paymentStatus) || "pending";
  return status === "seller_confirmed" || status === "paid";
}

function isCashOrder(order) {
  return String((order && order.paymentMethod) || "").toLowerCase() === "cash";
}

function canRevealOrderContact(order) {
  if (!order) return false;
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

function canRevealBuyerContact(order) {
  return canRevealOrderContact(order);
}

function canRevealSellerContact(order) {
  return canRevealOrderContact(order);
}

function viewerIsKitchenSeller(order, viewerUserId) {
  if (!viewerUserId) return false;
  const sellerId = kitchenSellerIdFromOrder(order);
  return Boolean(sellerId && sellerId === viewerUserId);
}

function viewerIsOrderBuyer(order, viewerUserId) {
  if (!viewerUserId || !order) return false;
  return Boolean(order.buyerId && order.buyerId === viewerUserId);
}

function serializeBuyerContactForViewer(order, viewerUserId) {
  const raw = (order && order.buyer && order.buyer.phone) || null;
  const kitchenSeller = viewerIsKitchenSeller(order, viewerUserId);
  const allowed = kitchenSeller && canRevealBuyerContact(order) && Boolean(raw);
  return {
    buyerPhone: null,
    buyerPhoneMasked: kitchenSeller ? maskBuyerPhone(raw) : null,
    canRevealBuyerPhone: allowed,
  };
}

function serializeSellerContactForViewer(order, viewerUserId) {
  const raw = sellerPhoneFromOrder(order);
  const isBuyer = viewerIsOrderBuyer(order, viewerUserId);
  const allowed = isBuyer && canRevealSellerContact(order) && Boolean(raw);
  return {
    sellerPhone: null,
    sellerPhoneMasked: isBuyer ? maskBuyerPhone(raw) : null,
    canRevealSellerPhone: allowed,
  };
}

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

async function revealPhoneWithAudit({
  actorId,
  action,
  orderId,
  phone,
  acknowledged,
  dailyCapMessage,
}) {
  const existing = await prisma.auditLog.findFirst({
    where: {
      adminId: actorId,
      action,
      target: orderId,
    },
    orderBy: { createdAt: "desc" },
  });
  if (existing) {
    return {
      phone,
      phoneMasked: maskBuyerPhone(phone),
    };
  }

  if (acknowledged !== true) {
    throw httpError(400, "Please confirm you will use this number only for this order.");
  }

  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const [orderCount, actorCount] = await Promise.all([
    prisma.auditLog.count({
      where: {
        action,
        target: orderId,
      },
    }),
    prisma.auditLog.count({
      where: {
        adminId: actorId,
        action,
        createdAt: { gte: dayAgo },
      },
    }),
  ]);
  if (orderCount >= MAX_REVEALS_PER_ORDER) {
    throw httpError(429, "Too many attempts to view this number. Try again later.");
  }
  if (actorCount >= MAX_NEW_ORDERS_PER_SELLER_DAY) {
    throw httpError(429, dailyCapMessage);
  }

  await prisma.auditLog.create({
    data: {
      adminId: actorId,
      action,
      target: orderId,
      details: "acknowledged",
    },
  });

  return {
    phone,
    phoneMasked: maskBuyerPhone(phone),
  };
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

  const revealed = await revealPhoneWithAudit({
    actorId: sellerId,
    action: REVEAL_ACTION,
    orderId: order.id,
    phone,
    acknowledged,
    dailyCapMessage: "Too many number views today. Try again tomorrow.",
  });
  return {
    buyerPhone: revealed.phone,
    buyerPhoneMasked: revealed.phoneMasked,
  };
}

async function revealSellerContact({ order, buyerId, acknowledged }) {
  if (!order) {
    throw httpError(404, "Order not found");
  }
  if (!order.buyerId || order.buyerId !== buyerId) {
    throw httpError(403, "Not allowed");
  }
  if (!canRevealSellerContact(order)) {
    throw httpError(
      400,
      "Kitchen number is available after the order is accepted and paid."
    );
  }
  const phone = sellerPhoneFromOrder(order);
  if (!phone) {
    throw httpError(400, "Kitchen number is not available for this order.");
  }

  const revealed = await revealPhoneWithAudit({
    actorId: buyerId,
    action: REVEAL_SELLER_ACTION,
    orderId: order.id,
    phone,
    acknowledged,
    dailyCapMessage: "Too many number views today. Try again tomorrow.",
  });
  return {
    sellerPhone: revealed.phone,
    sellerPhoneMasked: revealed.phoneMasked,
  };
}

module.exports = {
  REVEAL_ACTION,
  REVEAL_SELLER_ACTION,
  canRevealBuyerContact,
  canRevealSellerContact,
  maskBuyerPhone,
  serializeBuyerContactForViewer,
  serializeSellerContactForViewer,
  revealBuyerContact,
  revealSellerContact,
  viewerIsKitchenSeller,
  sellerPhoneFromOrder,
};
