const STATE_RANK = Object.freeze({
  quoted: 0,
  booked: 1,
  searching: 2,
  retrying: 2,
  assigned: 3,
  at_pickup: 4,
  picked_up: 5,
  at_delivery: 6,
  delivered: 7,
  cancelled: 8,
  rto: 8,
  failed: 8,
  seller_fallback: 8,
});

function rankOf(state) {
  const key = String(state || "").trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(STATE_RANK, key)
    ? STATE_RANK[key]
    : 0;
}

function mapProroutingState(raw) {
  const lower = String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/_+/g, "-")
    .replace(/-+/g, "-");
  if (lower === "created" || lower === "pending" || lower === "unfulfilled") {
    return "booked";
  }
  if (lower === "searching-for-agent") {
    return "searching";
  }
  if (lower === "agent-assigned") {
    return "assigned";
  }
  if (lower === "at-pickup") {
    return "at_pickup";
  }
  if (lower === "order-picked-up" || lower === "picked-up") {
    return "picked_up";
  }
  if (lower === "at-delivery") {
    return "at_delivery";
  }
  if (lower === "order-delivered") {
    return "delivered";
  }
  if (lower === "cancelled" || lower === "canceled") {
    return "cancelled";
  }
  if (lower.startsWith("rto")) {
    return "rto";
  }
  return null;
}

function isOlderThan(storedState, incomingState) {
  return rankOf(incomingState) < rankOf(storedState);
}

function fieldsFromProroutingOrder(remote) {
  if (!remote || typeof remote !== "object") return {};
  const rider = remote.rider || {};
  const lsp = remote.lsp || {};
  const mapped = mapProroutingState(
    remote.state ||
      remote.current_status ||
      remote.order_status ||
      (typeof remote.status === "string" ? remote.status : null)
  );
  return {
    ...(mapped ? { state: mapped } : {}),
    externalId: remote.id ? String(remote.id) : undefined,
    lspName:
      lsp.name ||
      remote.lsp_name ||
      (typeof remote.lsp === "string" ? remote.lsp : undefined) ||
      undefined,
    riderName: rider.name || undefined,
    riderPhone: rider.phone || undefined,
    trackingUrl: remote.tracking_url || remote.url || undefined,
    billedFare:
      remote.price != null && Number.isFinite(Number(remote.price))
        ? Number(remote.price)
        : undefined,
    lastPayload: JSON.stringify(remote).slice(0, 8000),
  };
}

const HUNTING_STATES = new Set(["quoted", "booked", "searching", "retrying"]);

function partnerSearchAction(task, nowMs, { retryAfterMs, fallbackAfterMs } = {}) {
  if (!task || !HUNTING_STATES.has(String(task.state || ""))) return "none";
  const start = new Date(task.bookedAt || task.createdAt || nowMs).getTime();
  if (!Number.isFinite(start)) return "none";
  const age = Number(nowMs) - start;
  const retryAfter = Number(retryAfterMs);
  const fallbackAfter = Number(fallbackAfterMs);
  if (Number.isFinite(fallbackAfter) && age >= fallbackAfter) return "fallback";
  if (
    Number.isFinite(retryAfter) &&
    age >= retryAfter &&
    Number(task.retryCount || 0) < 1
  ) {
    return "retry";
  }
  return "none";
}

function applyWebhookToTask(task, payload) {
  const remote = (payload && payload.order) || payload || {};
  const remoteId = remote.id ? String(remote.id) : "";
  if (task.externalId && remoteId && remoteId !== String(task.externalId)) {
    return { ignored: true, task };
  }
  const incoming = mapProroutingState(remote.state);
  const lspRetry =
    incoming === "booked" && rankOf(task.state) < rankOf("picked_up");
  if (incoming && isOlderThan(task.state, incoming) && !lspRetry) {
    return { ignored: true, task };
  }
  const next = {
    ...task,
    ...fieldsFromProroutingOrder(remote),
  };
  if (incoming) next.state = incoming;
  return { ignored: false, task: next };
}

module.exports = {
  STATE_RANK,
  rankOf,
  mapProroutingState,
  isOlderThan,
  fieldsFromProroutingOrder,
  applyWebhookToTask,
  HUNTING_STATES,
  partnerSearchAction,
};
