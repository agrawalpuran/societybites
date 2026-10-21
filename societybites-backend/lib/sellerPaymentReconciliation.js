const {
  formatIstYmd,
  addDaysYmd,
  startOfIstDay,
  endOfIstDay,
  resolveDateRange,
} = require("./sellerInsights");
const { money } = require("./coupons");
const {
  isFoodUpiConfirmed,
  deliveryCashSettled,
  isUpiFoodCashDeliverySplit,
  couponDiscountFromOrder,
} = require("./delayedDeliveryCharge");

const TERMINAL_EXCLUDE = new Set(["cancelled", "rejected"]);
const REMINDER_COOLDOWN_MS = 24 * 60 * 60 * 1000;
const DEFAULT_PAGE = 1;
const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 50;

function roundMoney(value) {
  return money(Number(value) || 0);
}

function resolveReconciliationRange(query = {}) {
  const preset = String(query.preset || "today").trim();
  const today = formatIstYmd(new Date());

  if (preset === "today") {
    return {
      preset: "today",
      fromYmd: today,
      toYmd: today,
      from: startOfIstDay(today),
      to: endOfIstDay(today),
      timezone: "Asia/Kolkata",
    };
  }
  if (preset === "yesterday") {
    const y = addDaysYmd(today, -1);
    return {
      preset: "yesterday",
      fromYmd: y,
      toYmd: y,
      from: startOfIstDay(y),
      to: endOfIstDay(y),
      timezone: "Asia/Kolkata",
    };
  }
  if (preset === "last_7_days") {
    const range = resolveDateRange({ preset: "last_7_days" });
    return { ...range, preset: "last_7_days" };
  }
  if (preset === "this_month") {
    const range = resolveDateRange({ preset: "this_month" });
    return { ...range, preset: "this_month" };
  }
  if (preset === "custom" || (query.from && query.to)) {
    const range = resolveDateRange({
      preset: "custom",
      from: query.from,
      to: query.to,
    });
    return { ...range, preset: "custom" };
  }

  const range = resolveDateRange({ preset: "today" });
  return { ...range, preset: "today" };
}

function sellerIdFromOrder(order) {
  const item = (order.items || []).find((row) => row.listing?.sellerId);
  return item ? item.listing.sellerId : null;
}

function isSalesEligible(order) {
  return order && !TERMINAL_EXCLUDE.has(order.status);
}

function isPaymentCollected(order) {
  if (!order || TERMINAL_EXCLUDE.has(order.status)) return false;
  if (order.paymentStatus === "failed") return false;
  if (!isFoodUpiConfirmed(order)) return false;
  if (!deliveryCashSettled(order)) return false;
  return true;
}

function reconciliationPhase(order) {
  return isPaymentCollected(order) ? "PAID" : "PENDING";
}

function orderAmount(order) {
  return roundMoney(order.total);
}

function collectionTimestamp(order) {
  if (!isPaymentCollected(order)) return null;
  const stamps = [
    order.sellerConfirmedPaidAt,
    order.deliveryCashConfirmedAt,
  ].filter(Boolean);
  if (stamps.length === 0) return null;
  return new Date(
    Math.max(...stamps.map((value) => new Date(value).getTime()))
  );
}

function inRange(date, range) {
  if (!date) return false;
  const t = new Date(date).getTime();
  return t >= range.from.getTime() && t <= range.to.getTime();
}

function locationBucket(order, buyer) {
  const societyId = buyer?.societyId || order.societyId;
  if (societyId) {
    return {
      type: "society",
      societyId,
      societyName: buyer?.society?.name || order.society?.name || "Society",
      buyerId: null,
      buyerName: null,
    };
  }
  return {
    type: "outside",
    societyId: null,
    societyName: null,
    buyerId: order.buyerId,
    buyerName: buyer?.name || "Customer",
  };
}

function emptyTotals() {
  return {
    totalSales: 0,
    collected: 0,
    pending: 0,
    pendingOrderCount: 0,
    orderCount: 0,
  };
}

function addToTotals(totals, order) {
  const amount = orderAmount(order);
  totals.orderCount += 1;
  totals.totalSales = roundMoney(totals.totalSales + amount);
  if (isPaymentCollected(order)) {
    totals.collected = roundMoney(totals.collected + amount);
  } else {
    totals.pending = roundMoney(totals.pending + amount);
    totals.pendingOrderCount += 1;
  }
}

function aggregateReconciliation(orders) {
  const summary = emptyTotals();
  const byMethod = {
    upi: emptyTotals(),
    cash: emptyTotals(),
  };
  const societies = new Map();
  const outsideBuyers = new Map();

  for (const order of orders) {
    if (!isSalesEligible(order)) continue;
    const buyer = order.buyer || {};
    const method = String(order.paymentMethod || "upi").toLowerCase();
    const methodKey = method === "cash" ? "cash" : "upi";

    addToTotals(summary, order);
    addToTotals(byMethod[methodKey], order);

    const loc = locationBucket(order, buyer);
    if (loc.type === "society") {
      if (!societies.has(loc.societyId)) {
        societies.set(loc.societyId, {
          societyId: loc.societyId,
          societyName: loc.societyName,
          ...emptyTotals(),
        });
      }
      addToTotals(societies.get(loc.societyId), order);
    } else {
      if (!outsideBuyers.has(loc.buyerId)) {
        outsideBuyers.set(loc.buyerId, {
          buyerId: loc.buyerId,
          buyerName: loc.buyerName,
          ...emptyTotals(),
        });
      }
      addToTotals(outsideBuyers.get(loc.buyerId), order);
    }
  }

  return {
    summary,
    byPaymentMethod: byMethod,
    societies: [...societies.values()].sort(
      (a, b) => b.pending - a.pending || b.totalSales - a.totalSales
    ),
    outsideBuyers: [...outsideBuyers.values()].sort(
      (a, b) => b.pending - a.pending || a.buyerName.localeCompare(b.buyerName)
    ),
  };
}

function aggregateCollectionsInRange(orders, range) {
  let collected = 0;
  let count = 0;
  for (const order of orders) {
    if (!isSalesEligible(order) || !isPaymentCollected(order)) continue;
    const at = collectionTimestamp(order);
    if (!inRange(at, range)) continue;
    collected = roundMoney(collected + orderAmount(order));
    count += 1;
  }
  return { collectedInPeriod: collected, collectedOrderCount: count };
}

const orderInclude = {
  buyer: {
    select: {
      id: true,
      name: true,
      phone: true,
      societyId: true,
      society: { select: { id: true, name: true } },
      flat: { select: { flatNumber: true, block: true } },
    },
  },
  society: { select: { id: true, name: true } },
  items: {
    include: {
      listing: {
        select: {
          id: true,
          name: true,
          sellerId: true,
          societyId: true,
        },
      },
    },
  },
  couponRedemptions: {
    where: { status: { in: ["REDEEMED"] } },
    select: { discountAmount: true, status: true },
    take: 1,
  },
};

async function loadSellerOrdersInSalesRange(prisma, sellerId, range) {
  return prisma.order.findMany({
    where: {
      createdAt: { gte: range.from, lte: range.to },
      items: { some: { listing: { sellerId } } },
    },
    include: orderInclude,
    orderBy: { createdAt: "desc" },
  });
}

async function getReconciliationSummary(prisma, sellerId, query) {
  const range = resolveReconciliationRange(query);
  const orders = await loadSellerOrdersInSalesRange(prisma, sellerId, range);
  const aggregated = aggregateReconciliation(orders);
  const collections = aggregateCollectionsInRange(orders, range);

  return {
    dateRange: {
      preset: range.preset,
      from: range.fromYmd,
      to: range.toYmd,
      timezone: range.timezone,
      endInclusive: true,
    },
    basis: {
      sales: "order_created_at_ist",
      collections: "payment_confirmed_at_ist",
      note:
        "Sales use orders created in the range (excludes cancelled/rejected). " +
        "Collected uses when payment was fully confirmed (sellerConfirmedPaidAt / delivery cash).",
    },
    summary: {
      ...aggregated.summary,
      collectedInPaymentPeriod: collections.collectedInPeriod,
      collectedOrdersInPaymentPeriod: collections.collectedOrderCount,
    },
    byPaymentMethod: aggregated.byPaymentMethod,
    locations: {
      societies: aggregated.societies,
      outsideBuyers: aggregated.outsideBuyers,
    },
  };
}

function parseListQuery(query) {
  const page = Math.max(1, parseInt(query.page, 10) || DEFAULT_PAGE);
  const limit = Math.min(MAX_LIMIT, Math.max(1, parseInt(query.limit, 10) || DEFAULT_LIMIT));
  return { page, limit, skip: (page - 1) * limit };
}

function matchesFilters(order, filters) {
  if (!isSalesEligible(order)) return false;
  if (filters.paymentPhase === "PAID" && reconciliationPhase(order) !== "PAID") {
    return false;
  }
  if (filters.paymentPhase === "PENDING" && reconciliationPhase(order) !== "PENDING") {
    return false;
  }
  const buyer = order.buyer || {};
  const loc = locationBucket(order, buyer);
  if (filters.locationType === "society" && loc.type !== "society") return false;
  if (filters.locationType === "outside" && loc.type !== "outside") return false;
  if (filters.societyId && loc.societyId !== filters.societyId) return false;
  if (filters.buyerId && loc.buyerId !== filters.buyerId) return false;
  if (filters.paymentMethod) {
    const method = String(order.paymentMethod || "").toLowerCase();
    if (method !== filters.paymentMethod) return false;
  }
  if (filters.search) {
    const q = filters.search.toLowerCase();
    const hay = [
      order.orderNumber,
      buyer.name,
      buyer.phone,
      loc.societyName,
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();
    if (!hay.includes(q)) return false;
  }
  return true;
}

function serializeReconciliationOrder(order) {
  const buyer = order.buyer || {};
  const loc = locationBucket(order, buyer);
  const discount = couponDiscountFromOrder(order);
  return {
    id: order.id,
    orderNumber: order.orderNumber,
    createdAt: order.createdAt,
    status: order.status,
    paymentMethod: order.paymentMethod,
    paymentStatus: order.paymentStatus,
    paymentPhase: reconciliationPhase(order),
    subtotal: roundMoney(order.subtotal),
    deliveryCharge: roundMoney(order.deliveryCharge),
    communityFee: roundMoney(order.communityFee),
    couponDiscount: roundMoney(discount),
    total: orderAmount(order),
    outstandingAmount: isPaymentCollected(order) ? 0 : orderAmount(order),
    buyer: {
      id: buyer.id,
      name: buyer.name,
      phone: buyer.phone,
    },
    location: loc,
    fulfilmentMethod: order.fulfilmentMethod,
    isUpiSplitDelivery: isUpiFoodCashDeliverySplit(order),
    lastPaymentReminderAt: order.lastPaymentReminderAt || null,
    items: (order.items || []).map((row) => ({
      listingId: row.listingId,
      name: row.listing?.name,
      quantity: row.quantity,
      unitPrice: roundMoney(row.unitPrice),
    })),
  };
}

async function listReconciliationOrders(prisma, sellerId, query) {
  const range = resolveReconciliationRange(query);
  const { page, limit, skip } = parseListQuery(query);
  const filters = {
    paymentPhase: String(query.paymentPhase || "").trim().toUpperCase() || null,
    locationType: String(query.locationType || "").trim().toLowerCase() || null,
    societyId: query.societyId ? String(query.societyId) : null,
    buyerId: query.buyerId ? String(query.buyerId) : null,
    paymentMethod: query.paymentMethod
      ? String(query.paymentMethod).trim().toLowerCase()
      : null,
    search: query.search ? String(query.search).trim().toLowerCase() : null,
  };

  const orders = await loadSellerOrdersInSalesRange(prisma, sellerId, range);
  const filtered = orders.filter((order) => matchesFilters(order, filters));
  const pageRows = filtered.slice(skip, skip + limit).map(serializeReconciliationOrder);

  return {
    dateRange: {
      preset: range.preset,
      from: range.fromYmd,
      to: range.toYmd,
      timezone: range.timezone,
    },
    page,
    limit,
    total: filtered.length,
    orders: pageRows,
  };
}

function assertSellerOwnsOrder(order, sellerId) {
  return sellerIdFromOrder(order) === sellerId;
}

function canSendPaymentReminder(order) {
  if (!order || TERMINAL_EXCLUDE.has(order.status)) {
    return { ok: false, reason: "ORDER_NOT_ELIGIBLE" };
  }
  if (isPaymentCollected(order)) {
    return { ok: false, reason: "ALREADY_PAID" };
  }
  if (order.lastPaymentReminderAt) {
    const elapsed = Date.now() - new Date(order.lastPaymentReminderAt).getTime();
    if (elapsed < REMINDER_COOLDOWN_MS) {
      return { ok: false, reason: "COOLDOWN", retryAfterMs: REMINDER_COOLDOWN_MS - elapsed };
    }
  }
  return { ok: true };
}

module.exports = {
  resolveReconciliationRange,
  isPaymentCollected,
  reconciliationPhase,
  getReconciliationSummary,
  listReconciliationOrders,
  serializeReconciliationOrder,
  assertSellerOwnsOrder,
  canSendPaymentReminder,
  REMINDER_COOLDOWN_MS,
  orderInclude,
};
