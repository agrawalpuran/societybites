const BUYER_TERMINAL_ACTIVE_MS = 24 * 60 * 60 * 1000;

function terminalOccurredAt(order) {
  const status = order.status;
  const timeline = order.timeline || {};
  if (status === "completed") {
    return order.completedAt || timeline.completedAt || null;
  }
  if (status === "rejected") {
    return order.rejectedAt || timeline.rejectedAt || null;
  }
  if (status === "cancelled") {
    return order.cancelledAt || timeline.cancelledAt || null;
  }
  return null;
}

function isBuyerActiveOrder(order, now = new Date()) {
  const status = order.status;
  if (status !== "completed" && status !== "rejected" && status !== "cancelled") {
    return true;
  }
  const at = terminalOccurredAt(order);
  if (!at) return false;
  return now.getTime() - new Date(at).getTime() < BUYER_TERMINAL_ACTIVE_MS;
}

module.exports = {
  BUYER_TERMINAL_ACTIVE_MS,
  terminalOccurredAt,
  isBuyerActiveOrder,
};
