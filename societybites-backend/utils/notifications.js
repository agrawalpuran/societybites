const prisma = require("../lib/prisma");
const logger = require("../lib/logger");
const { getMessaging } = require("../lib/firebase");

const INVALID_TOKEN_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

const IST = "Asia/Kolkata";

/** Clock time for push copy. The server process is UTC, so this must not use the host timezone. */
function formatNotificationTime(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: IST,
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
    hourCycle: "h12",
  }).formatToParts(date);
  const part = (type) => parts.find((item) => item.type === type)?.value || "";
  const dayPeriod = part("dayPeriod").toUpperCase();
  return `${part("day")} ${part("month")}, ${part("hour")}:${part("minute")} ${dayPeriod}`;
}

/** Must match Android MainActivity CHANNEL_ID and AndroidManifest default channel. */
const ANDROID_CHANNEL_ID = "societybites_orders";

/** Upper bound on how long we keep a handler alive waiting for FCM. */
const NOTIFY_TIMEOUT_MS = Number(process.env.NOTIFY_TIMEOUT_MS || 8000);

/**
 * Never throws to callers; never used inside Prisma txns. Returns a promise so
 * routes can keep the send tracked instead of leaving it unobserved.
 */
function notifyAsync(fn) {
  return Promise.resolve()
    .then(fn)
    .catch((err) => {
      logger.error("notify", err.message || String(err));
    });
}

/**
 * Run a notify* call to completion after the response has been sent, so the
 * send is never left unobserved but never adds latency to the request either.
 */
async function flushNotification(pending) {
  if (!pending || typeof pending.then !== "function") return;
  let timer;
  try {
    await Promise.race([
      pending,
      new Promise((resolve) => {
        timer = setTimeout(() => {
          logger.warn("notify", `FCM send still pending after ${NOTIFY_TIMEOUT_MS}ms`);
          resolve();
        }, NOTIFY_TIMEOUT_MS);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function sellerIdFromOrder(order) {
  return order?.items?.[0]?.listing?.sellerId || null;
}

function buildFcmMessage(token, { title, body, data }) {
  return {
    token,
    notification: { title, body },
    data,
    android: {
      priority: "high",
      notification: {
        channelId: ANDROID_CHANNEL_ID,
        sound: "default",
      },
    },
    apns: {
      headers: {
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      payload: {
        aps: {
          alert: { title, body },
          sound: "default",
        },
      },
    },
  };
}

/**
 * Send a push to all active tokens for a user.
 * @param {string} userId
 * @param {{ title: string, body: string, notificationType: string, orderId: string }} opts
 */
async function sendToUser(userId, { title, body, notificationType, orderId, extra }) {
  if (!userId || !notificationType || !orderId) return;

  const tokens = await prisma.deviceToken.findMany({
    where: { userId, active: true },
    select: { id: true, token: true },
  });

  if (tokens.length === 0) {
    logger.info("notify", `No active device tokens (${notificationType})`);
    return;
  }

  const messaging = getMessaging();
  const data = {
    type: "order_update",
    orderId: String(orderId),
    notificationType: String(notificationType),
    ...(extra && typeof extra === "object" ? extra : {}),
  };
  for (const key of Object.keys(data)) {
    data[key] = String(data[key] ?? "");
  }

  const staleIds = [];
  let sent = 0;

  await Promise.all(
    tokens.map(async ({ id, token }) => {
      try {
        await messaging.send(buildFcmMessage(token, { title, body, data }));
        sent += 1;
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

  if (sent > 0) {
    logger.info("notify", `FCM sent ${sent} (${notificationType})`);
  }

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
  return notifyAsync(() =>
    sendToUser(sellerId, {
      title: "New SocietyBites order",
      body: `Order ${order.orderNumber} is waiting for you`,
      notificationType: "order_created",
      orderId: order.id,
      extra: {
        status: String(order.status || "pending"),
        paymentStatus: String(order.paymentStatus || "pending"),
        recipientRole: "seller",
      },
    })
  );
}

function notifyStatusChange(order, status) {
  const sellerId = sellerIdFromOrder(order);
  const buyerId = order.buyerId;

  const map = {
    accepted: {
      userId: buyerId,
      title: "Order confirmed",
      body: "Your order has been confirmed.",
      notificationType: "order_accepted",
    },
    ready: {
      userId: buyerId,
      title: "Ready for pickup",
      body: "Your order is ready for pickup.",
      notificationType: "order_ready",
    },
    cancelled: {
      userId: sellerId,
      title: "Order cancelled",
      body: order.cancelReason
        ? `Order ${order.orderNumber} was cancelled: ${String(order.cancelReason).split("\n")[0]}`
        : `Order ${order.orderNumber} was cancelled`,
      notificationType: "order_cancelled",
    },
    completed: {
      userId: buyerId,
      title: "Order completed",
      body: `Order ${order.orderNumber} is complete`,
      notificationType: "order_completed",
    },
  };

  const cfg = map[status];
  if (!cfg?.userId) return;

  return notifyAsync(() =>
    sendToUser(cfg.userId, {
      title: cfg.title,
      body: cfg.body,
      notificationType: cfg.notificationType,
      orderId: order.id,
      extra: { status: String(status) },
    })
  );
}

function notifyOrderRejected(order) {
  return notifyAsync(() =>
    sendToUser(order.buyerId, {
      title: "Order rejected",
      body: "Unfortunately, the seller could not fulfil your order.",
      notificationType: "order_rejected",
      orderId: order.id,
      extra: { status: "rejected" },
    })
  );
}

function notifyReadyBy(order, cleared) {
  if (cleared) return; // skip per Phase 1 design (optional)
  const when = order.expectedReadyAt
    ? formatNotificationTime(order.expectedReadyAt)
    : "";
  return notifyAsync(() =>
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
  return notifyAsync(() =>
    sendToUser(sellerId, {
      title: "Buyer marked paid",
      body: `Payment marked for order ${order.orderNumber}`,
      notificationType: "buyer_marked_paid",
      orderId: order.id,
      extra: { paymentStatus: "buyer_marked_paid" },
    })
  );
}

/** Payment confirmation does not change order status. */
function notifyPaymentConfirmed(order) {
  const isCash = order.paymentMethod === "cash";
  const paymentStatus = order.paymentStatus || "seller_confirmed";
  return notifyAsync(() =>
    sendToUser(order.buyerId, {
      title: isCash ? "Payment received" : "Payment confirmed",
      body: isCash
        ? `Payment received for order ${order.orderNumber}`
        : `Payment confirmed for order ${order.orderNumber}`,
      notificationType: "payment_confirmed",
      orderId: order.id,
      extra: { paymentStatus: String(paymentStatus) },
    })
  );
}

function notifyOrderMessage(order, senderId) {
  const sellerId = sellerIdFromOrder(order);
  const recipientId = senderId === order.buyerId ? sellerId : order.buyerId;
  if (!recipientId || recipientId === senderId) return;
  const fromSeller = senderId === sellerId;
  return notifyAsync(() =>
    sendToUser(recipientId, {
      title: fromSeller ? "New message from seller" : "New message from buyer",
      body: `Order ${order.orderNumber} has a new message`,
      notificationType: "order_message",
      orderId: order.id,
      extra: { recipientRole: fromSeller ? "buyer" : "seller" },
    })
  );
}

module.exports = {
  ANDROID_CHANNEL_ID,
  formatNotificationTime,
  notifyAsync,
  flushNotification,
  sendToUser,
  buildFcmMessage,
  notifyOrderCreated,
  notifyStatusChange,
  notifyOrderRejected,
  notifyReadyBy,
  notifyBuyerMarkedPaid,
  notifyPaymentConfirmed,
  notifyOrderMessage,
};
