const prisma = require("../lib/prisma");
const logger = require("../lib/logger");
const { getMessaging } = require("../lib/firebase");

const INVALID_TOKEN_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

/**
 * Fire-and-forget wrapper — never throws to callers; never used inside Prisma txns.
 */
function notifyAsync(fn) {
  Promise.resolve()
    .then(fn)
    .catch((err) => {
      logger.error("notify", err.message || String(err));
    });
}

function sellerIdFromOrder(order) {
  return order?.items?.[0]?.listing?.sellerId || null;
}

/**
 * Send a push to all active tokens for a user.
 * @param {string} userId
 * @param {{ title: string, body: string, notificationType: string, orderId: string }} opts
 */
async function sendToUser(userId, { title, body, notificationType, orderId }) {
  if (!userId || !notificationType || !orderId) return;

  const tokens = await prisma.deviceToken.findMany({
    where: { userId, active: true },
    select: { id: true, token: true },
  });

  if (tokens.length === 0) return;

  const messaging = getMessaging();
  const data = {
    type: "order_update",
    orderId: String(orderId),
    notificationType: String(notificationType),
  };

  const staleIds = [];

  await Promise.all(
    tokens.map(async ({ id, token }) => {
      try {
        await messaging.send({
          token,
          notification: { title, body },
          data,
          android: { priority: "high" },
        });
      } catch (err) {
        const code = err?.code || "";
        if (INVALID_TOKEN_CODES.has(code)) {
          staleIds.push(id);
        } else {
          logger.warn("notify", `FCM send failed: ${err.message || code}`, {
            notificationType,
            orderId,
          });
        }
      }
    })
  );

  if (staleIds.length > 0) {
    await prisma.deviceToken.updateMany({
      where: { id: { in: staleIds } },
      data: { active: false },
    });
    logger.info("notify", `Deactivated ${staleIds.length} stale device token(s)`);
  }
}

function notifyOrderCreated(order) {
  const sellerId = sellerIdFromOrder(order);
  if (!sellerId) return;
  notifyAsync(() =>
    sendToUser(sellerId, {
      title: "New SocietyBites order",
      body: `Order ${order.orderNumber} is waiting for you`,
      notificationType: "order_created",
      orderId: order.id,
    })
  );
}

function notifyStatusChange(order, status) {
  const sellerId = sellerIdFromOrder(order);
  const buyerId = order.buyerId;

  const map = {
    accepted: {
      userId: buyerId,
      title: "Order accepted",
      body: `Order ${order.orderNumber} was accepted`,
      notificationType: "order_accepted",
    },
    preparing: {
      userId: buyerId,
      title: "Order preparing",
      body: `Order ${order.orderNumber} is being prepared`,
      notificationType: "order_preparing",
    },
    ready: {
      userId: buyerId,
      title: "Ready for pickup",
      body: `Order ${order.orderNumber} is ready for pickup`,
      notificationType: "order_ready",
    },
    cancelled: {
      userId: sellerId,
      title: "Order cancelled",
      body: `Order ${order.orderNumber} was cancelled`,
      notificationType: "order_cancelled",
    },
    picked_up: {
      userId: sellerId,
      title: "Order picked up",
      body: `Order ${order.orderNumber} was marked picked up`,
      notificationType: "order_picked_up",
    },
    completed: {
      userId: sellerId,
      title: "Order completed",
      body: `Order ${order.orderNumber} is complete`,
      notificationType: "order_completed",
    },
  };

  const cfg = map[status];
  if (!cfg?.userId) return;

  notifyAsync(() =>
    sendToUser(cfg.userId, {
      title: cfg.title,
      body: cfg.body,
      notificationType: cfg.notificationType,
      orderId: order.id,
    })
  );
}

function notifyOrderRejected(order) {
  const reason = order.rejectReason ? ` — ${order.rejectReason}` : "";
  notifyAsync(() =>
    sendToUser(order.buyerId, {
      title: "Order rejected",
      body: `Order ${order.orderNumber} was rejected${reason}`.slice(0, 180),
      notificationType: "order_rejected",
      orderId: order.id,
    })
  );
}

function notifyReadyBy(order, cleared) {
  if (cleared) return; // skip per Phase 1 design (optional)
  const when = order.expectedReadyAt
    ? new Date(order.expectedReadyAt).toLocaleString()
    : "";
  notifyAsync(() =>
    sendToUser(order.buyerId, {
      title: "Ready by updated",
      body: when
        ? `Order ${order.orderNumber} ready by ${when}`
        : `Ready by time updated for ${order.orderNumber}`,
      notificationType: "ready_by_updated",
      orderId: order.id,
    })
  );
}

function notifyBuyerMarkedPaid(order) {
  const sellerId = sellerIdFromOrder(order);
  if (!sellerId) return;
  notifyAsync(() =>
    sendToUser(sellerId, {
      title: "Buyer marked paid",
      body: `Payment marked for order ${order.orderNumber}`,
      notificationType: "buyer_marked_paid",
      orderId: order.id,
    })
  );
}

/** Payment confirm also moves to preparing — one buyer notification only. */
function notifyPaymentConfirmed(order) {
  const isCash = order.paymentMethod === "cash";
  notifyAsync(() =>
    sendToUser(order.buyerId, {
      title: isCash ? "Payment received" : "Payment confirmed",
      body: isCash
        ? `Payment received for order ${order.orderNumber}`
        : `Payment confirmed for order ${order.orderNumber}`,
      notificationType: "payment_confirmed",
      orderId: order.id,
    })
  );
}

module.exports = {
  notifyAsync,
  sendToUser,
  notifyOrderCreated,
  notifyStatusChange,
  notifyOrderRejected,
  notifyReadyBy,
  notifyBuyerMarkedPaid,
  notifyPaymentConfirmed,
};
