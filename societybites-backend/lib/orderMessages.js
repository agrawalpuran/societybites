const MAX_MESSAGE_LENGTH = 500;

function assertOrderParticipant(order, userId) {
  if (!order) {
    const err = new Error("Order not found");
    err.statusCode = 404;
    throw err;
  }

  const isBuyer = order.buyerId === userId;
  const isSeller = (order.items || []).some(
    (item) => item.listing && item.listing.sellerId === userId
  );

  if (!isBuyer && !isSeller) {
    const err = new Error("Not allowed to access this conversation");
    err.statusCode = 403;
    throw err;
  }

  return { isBuyer, isSeller };
}

function parseMessageBody(raw) {
  if (raw == null) {
    const err = new Error("message is required");
    err.statusCode = 400;
    throw err;
  }

  const message = String(raw).trim();
  if (!message) {
    const err = new Error("message cannot be empty");
    err.statusCode = 400;
    throw err;
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    const err = new Error(`message must be at most ${MAX_MESSAGE_LENGTH} characters`);
    err.statusCode = 400;
    throw err;
  }
  return message;
}

function serializeMessage(row, order) {
  const isBuyerSender = order && row.senderId === order.buyerId;
  return {
    id: row.id,
    orderId: row.orderId,
    senderId: row.senderId,
    message: row.message,
    createdAt: row.createdAt,
    readAt: row.readAt,
    senderRole: isBuyerSender ? "buyer" : "seller",
  };
}

async function attachUnreadCounts(prisma, orders, userId) {
  if (!orders.length) return orders;
  const grouped = await prisma.message.groupBy({
    by: ["orderId"],
    where: {
      orderId: { in: orders.map((order) => order.id) },
      senderId: { not: userId },
      readAt: null,
    },
    _count: { _all: true },
  });
  const byId = Object.fromEntries(
    grouped.map((row) => [row.orderId, row._count._all])
  );
  return orders.map((order) => ({
    ...order,
    unreadMessageCount: byId[order.id] || 0,
  }));
}

module.exports = {
  MAX_MESSAGE_LENGTH,
  assertOrderParticipant,
  parseMessageBody,
  serializeMessage,
  attachUnreadCounts,
};
