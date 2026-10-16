const {
  resolveDateRange,
  formatIstYmd,
  startOfIstDay,
  endOfIstDay,
  QUALIFYING_SALES_STATUS,
} = require("./sellerInsights");

const TERMINAL_FAILURE_STATUSES = new Set(["cancelled", "rejected"]);
const LEADERBOARD_SORT = new Set([
  "netFoodSales",
  "grossFoodSales",
  "qualifyingOrders",
  "uniqueBuyers",
  "cancellationRate",
]);
const DEFAULT_SORT = "netFoodSales";
const DEFAULT_PAGE = 1;
const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;
const MAX_EXPORT_ROWS = 5000;
const ALL_TIME_FROM_YMD = "2020-01-01";

function roundMoney(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function sellerIdFromOrder(order) {
  const item = (order.items || []).find((row) => row.listing && row.listing.sellerId);
  return item ? item.listing.sellerId : null;
}

function discountOnOrder(order) {
  const rows = order.couponRedemptions || [];
  const redeemed = rows.find((row) => row.status === "REDEEMED");
  return redeemed ? Number(redeemed.discountAmount || 0) : 0;
}

function resolvePerformanceRange(query = {}) {
  const preset = String(query.preset || "last_7_days").trim();
  if (preset === "all_time") {
    const today = formatIstYmd(new Date());
    return {
      preset: "all_time",
      fromYmd: ALL_TIME_FROM_YMD,
      toYmd: today,
      from: startOfIstDay(ALL_TIME_FROM_YMD),
      to: endOfIstDay(today),
      timezone: "Asia/Kolkata",
      endInclusive: true,
    };
  }
  const range = resolveDateRange({
    preset: preset === "last_30_days" || preset === "last_7_days" || preset === "custom"
      ? preset
      : query.from && query.to
        ? "custom"
        : "last_7_days",
    from: query.from,
    to: query.to,
  });
  return range;
}

function buildOrderWhere(range, societyId) {
  return {
    createdAt: { gte: range.from, lte: range.to },
    ...(societyId ? { societyId: String(societyId) } : {}),
  };
}

const orderSelect = {
  id: true,
  orderNumber: true,
  buyerId: true,
  societyId: true,
  status: true,
  type: true,
  campaignId: true,
  subtotal: true,
  deliveryCharge: true,
  communityFee: true,
  total: true,
  paymentMethod: true,
  paymentStatus: true,
  buyerMarkedPaidAt: true,
  cancelReason: true,
  createdAt: true,
  completedAt: true,
  couponRedemptions: {
    select: { status: true, discountAmount: true },
  },
  items: {
    select: {
      quantity: true,
      unitPrice: true,
      listing: {
        select: {
          sellerId: true,
          seller: { select: { id: true, name: true, phone: true, societyId: true } },
        },
      },
    },
  },
  buyer: { select: { id: true, name: true } },
  society: { select: { id: true, name: true } },
  campaign: { select: { id: true, title: true, status: true } },
};

function emptySellerRow(seller) {
  return {
    sellerId: seller.id,
    sellerName: seller.name || "Seller",
    sellerPhone: seller.phone || null,
    societyId: seller.societyId || null,
    societyName: seller.society?.name || null,
    grossFoodSales: 0,
    netFoodSales: 0,
    deliveryCharges: 0,
    qualifyingOrders: 0,
    uniqueBuyers: new Set(),
    ordersCreated: 0,
    cancelledCount: 0,
    rejectedCount: 0,
    newBuyers: 0,
    repeatBuyers: 0,
    paymentStatusCounts: {},
  };
}

function aggregateOrders(orders) {
  const bySeller = new Map();
  const paymentStatusCounts = {};
  const paymentMethodCounts = {};
  let grossFood = 0;
  let netFood = 0;
  let deliveryTotal = 0;
  let qualifyingOrders = 0;
  const globalBuyers = new Set();

  for (const order of orders) {
    const sellerId = sellerIdFromOrder(order);
    if (!sellerId) continue;

    const sellerMeta =
      (order.items || [])
        .map((item) => item.listing && item.listing.seller)
        .find(Boolean) || { id: sellerId };

    if (!bySeller.has(sellerId)) {
      bySeller.set(sellerId, emptySellerRow(sellerMeta));
    }
    const row = bySeller.get(sellerId);
    row.ordersCreated += 1;

    paymentStatusCounts[order.paymentStatus] =
      (paymentStatusCounts[order.paymentStatus] || 0) + 1;
    paymentMethodCounts[order.paymentMethod] =
      (paymentMethodCounts[order.paymentMethod] || 0) + 1;
    row.paymentStatusCounts[order.paymentStatus] =
      (row.paymentStatusCounts[order.paymentStatus] || 0) + 1;

    if (order.status === "cancelled") row.cancelledCount += 1;
    if (order.status === "rejected") row.rejectedCount += 1;

    if (order.status !== QUALIFYING_SALES_STATUS) continue;

    const discount = discountOnOrder(order);
    const gross = Number(order.subtotal || 0);
    const net = Math.max(0, gross - discount);
    const delivery = Number(order.deliveryCharge || 0);

    qualifyingOrders += 1;
    grossFood += gross;
    netFood += net;
    deliveryTotal += delivery;
    row.qualifyingOrders += 1;
    row.grossFoodSales += gross;
    row.netFoodSales += net;
    row.deliveryCharges += delivery;
    row.uniqueBuyers.add(order.buyerId);
    globalBuyers.add(order.buyerId);
  }

  return {
    bySeller,
    summary: {
      grossFoodSales: roundMoney(grossFood),
      netFoodSales: roundMoney(netFood),
      deliveryCharges: roundMoney(deliveryTotal),
      qualifyingOrders,
      uniqueBuyers: globalBuyers.size,
      averageNetFoodOrderValue:
        qualifyingOrders > 0 ? roundMoney(netFood / qualifyingOrders) : 0,
    },
    paymentStatusCounts,
    paymentMethodCounts,
  };
}

async function loadOrdersForRange(prisma, range, societyId) {
  return prisma.order.findMany({
    where: buildOrderWhere(range, societyId),
    select: orderSelect,
    orderBy: { createdAt: "desc" },
    take: MAX_EXPORT_ROWS + 1,
  });
}

async function enrichBuyerNewRepeat(prisma, sellerId, orders, range) {
  const completedBuyerIds = [
    ...new Set(
      orders
        .filter((o) => o.status === QUALIFYING_SALES_STATUS)
        .map((o) => o.buyerId)
    ),
  ];
  if (completedBuyerIds.length === 0) {
    return { newBuyers: 0, repeatBuyers: 0 };
  }

  const prior = await prisma.order.findMany({
    where: {
      status: QUALIFYING_SALES_STATUS,
      buyerId: { in: completedBuyerIds },
      createdAt: { lt: range.from },
      items: { some: { listing: { sellerId } } },
    },
    select: { buyerId: true },
    distinct: ["buyerId"],
  });
  const priorSet = new Set(prior.map((row) => row.buyerId));

  let newBuyers = 0;
  let repeatBuyers = 0;
  const seen = new Set();
  for (const order of orders) {
    if (order.status !== QUALIFYING_SALES_STATUS) continue;
    if (seen.has(order.buyerId)) continue;
    seen.add(order.buyerId);
    if (priorSet.has(order.buyerId)) repeatBuyers += 1;
    else newBuyers += 1;
  }
  return { newBuyers, repeatBuyers };
}

function serializeSellerRow(row) {
  const denom = row.ordersCreated || 0;
  const failures = row.cancelledCount + row.rejectedCount;
  return {
    sellerId: row.sellerId,
    sellerName: row.sellerName,
    sellerPhone: row.sellerPhone,
    societyId: row.societyId,
    societyName: row.societyName,
    grossFoodSales: roundMoney(row.grossFoodSales),
    netFoodSales: roundMoney(row.netFoodSales),
    deliveryCharges: roundMoney(row.deliveryCharges),
    qualifyingOrders: row.qualifyingOrders,
    uniqueBuyers: row.uniqueBuyers.size,
    ordersCreated: row.ordersCreated,
    cancelledCount: row.cancelledCount,
    rejectedCount: row.rejectedCount,
    cancellationRate: denom > 0 ? roundMoney(failures / denom) : 0,
    paymentStatusCounts: row.paymentStatusCounts,
  };
}

function sortLeaderboard(rows, sortKey) {
  const key = LEADERBOARD_SORT.has(sortKey) ? sortKey : DEFAULT_SORT;
  const sorted = [...rows];
  sorted.sort((a, b) => {
    if (key === "cancellationRate") {
      return b.cancellationRate - a.cancellationRate || b.ordersCreated - a.ordersCreated;
    }
    return (b[key] || 0) - (a[key] || 0) || a.sellerName.localeCompare(b.sellerName);
  });
  return sorted;
}

const PAYMENT_STUCK_MS = 24 * 60 * 60 * 1000;
const HIGH_CANCEL_RATE = 0.2;
const MIN_ORDERS_FOR_CANCEL_SIGNAL = 3;
const HIGH_DISCOUNT_RATIO = 0.4;
const DAILY_ORDER_VELOCITY_THRESHOLD = 8;
const MAX_SIGNAL_ROWS = 20;

function sellerNameFromOrder(order) {
  const seller = (order.items || [])
    .map((item) => item.listing && item.listing.seller)
    .find(Boolean);
  return seller?.name || "Seller";
}

function isOpenOrderStatus(status) {
  return !TERMINAL_FAILURE_STATUSES.has(status) && status !== QUALIFYING_SALES_STATUS;
}

/**
 * Read-only heuristics for admin review (not automated enforcement).
 */
function computePatternSignals(orders) {
  const { bySeller } = aggregateOrders(orders);
  const highlights = [];
  const paymentStuckOrders = [];
  const buyerFailureMap = new Map();
  const sellerDayCounts = new Map();
  let buyerMarkedAwaitingSeller = 0;
  let highDiscountOrders = 0;

  for (const order of orders) {
    const sellerId = sellerIdFromOrder(order);
    if (!sellerId) continue;

    if (
      order.paymentStatus === "buyer_marked_paid" &&
      isOpenOrderStatus(order.status)
    ) {
      buyerMarkedAwaitingSeller += 1;
      const markedAt = order.buyerMarkedPaidAt
        ? new Date(order.buyerMarkedPaidAt).getTime()
        : new Date(order.createdAt).getTime();
      if (Date.now() - markedAt > PAYMENT_STUCK_MS) {
        paymentStuckOrders.push({
          orderId: order.id,
          orderNumber: order.orderNumber,
          sellerId,
          sellerName: sellerNameFromOrder(order),
          buyerName: order.buyer?.name || "Buyer",
          status: order.status,
          paymentStatus: order.paymentStatus,
          createdAt: order.createdAt,
          subtotal: roundMoney(order.subtotal),
        });
      }
    }

    if (TERMINAL_FAILURE_STATUSES.has(order.status)) {
      const entry = buyerFailureMap.get(order.buyerId) || {
        buyerId: order.buyerId,
        buyerName: order.buyer?.name || "Buyer",
        failures: 0,
        sellerIds: new Set(),
      };
      entry.failures += 1;
      entry.sellerIds.add(sellerId);
      buyerFailureMap.set(order.buyerId, entry);
    }

    const gross = Number(order.subtotal || 0);
    const discount = discountOnOrder(order);
    if (gross > 0 && discount / gross >= HIGH_DISCOUNT_RATIO) {
      highDiscountOrders += 1;
    }

    const dayKey = `${sellerId}:${formatIstYmd(order.createdAt)}`;
    sellerDayCounts.set(dayKey, (sellerDayCounts.get(dayKey) || 0) + 1);
  }

  for (const row of bySeller.values()) {
    const failures = row.cancelledCount + row.rejectedCount;
    const rate = row.ordersCreated > 0 ? failures / row.ordersCreated : 0;
    if (row.ordersCreated >= MIN_ORDERS_FOR_CANCEL_SIGNAL && rate >= HIGH_CANCEL_RATE) {
      highlights.push({
        severity: rate >= 0.35 ? "high" : "medium",
        code: "HIGH_CANCEL_OR_REJECT_RATE",
        sellerId: row.sellerId,
        sellerName: row.sellerName,
        message: `${Math.round(rate * 100)}% cancelled/rejected (${failures}/${row.ordersCreated} orders)`,
      });
    }
  }

  for (const [dayKey, count] of sellerDayCounts.entries()) {
    if (count < DAILY_ORDER_VELOCITY_THRESHOLD) continue;
    const [sellerId, date] = dayKey.split(":");
    const row = bySeller.get(sellerId);
    highlights.push({
      severity: "medium",
      code: "HIGH_DAILY_ORDER_VOLUME",
      sellerId,
      sellerName: row?.sellerName || "Seller",
      message: `${count} orders on ${date} (IST) — check for abuse or bulk testing`,
    });
  }

  const repeatIssueBuyers = [...buyerFailureMap.values()]
    .filter((entry) => entry.failures >= 2)
    .map((entry) => ({
      buyerId: entry.buyerId,
      buyerName: entry.buyerName,
      failures: entry.failures,
      sellerCount: entry.sellerIds.size,
    }))
    .sort((a, b) => b.failures - a.failures);

  for (const buyer of repeatIssueBuyers.slice(0, 5)) {
    highlights.push({
      severity: buyer.failures >= 3 ? "high" : "medium",
      code: "REPEAT_CANCELLED_BUYER",
      buyerId: buyer.buyerId,
      buyerName: buyer.buyerName,
      message: `${buyer.failures} cancelled/rejected orders in range`,
    });
  }

  return {
    disclaimer:
      "Signals are heuristics for manual review only. Open Admin → Orders for full buyer/seller/payment detail.",
    counts: {
      buyerMarkedAwaitingSeller,
      paymentStuckOver24h: paymentStuckOrders.length,
      highDiscountOrders,
      repeatIssueBuyers: repeatIssueBuyers.length,
    },
    highlights: highlights.slice(0, MAX_SIGNAL_ROWS),
    paymentStuckOrders: paymentStuckOrders.slice(0, 15),
    repeatIssueBuyers: repeatIssueBuyers.slice(0, 15),
  };
}

function computeSellerPatternSignals(orders, sellerId) {
  const sellerOrders = orders.filter((o) => sellerIdFromOrder(o) === sellerId);
  const signals = computePatternSignals(sellerOrders);
  const cancelReasons = {};
  for (const order of sellerOrders) {
    if (!TERMINAL_FAILURE_STATUSES.has(order.status)) continue;
    const reason = (order.cancelReason || order.status || "unknown").split("\n")[0];
    cancelReasons[reason] = (cancelReasons[reason] || 0) + 1;
  }
  return {
    ...signals,
    cancelReasons,
    recentFlaggedOrders: sellerOrders
      .filter(
        (o) =>
          TERMINAL_FAILURE_STATUSES.has(o.status) ||
          (o.paymentStatus === "buyer_marked_paid" && isOpenOrderStatus(o.status))
      )
      .slice(0, 12)
      .map((o) => ({
        orderNumber: o.orderNumber,
        status: o.status,
        paymentStatus: o.paymentStatus,
        paymentMethod: o.paymentMethod,
        subtotal: roundMoney(o.subtotal),
        buyerName: o.buyer?.name || "Buyer",
        createdAt: o.createdAt,
        cancelReason: o.cancelReason,
      })),
  };
}

function parsePageLimit(query) {
  const page = Math.max(1, parseInt(query.page, 10) || DEFAULT_PAGE);
  const limit = Math.min(MAX_LIMIT, Math.max(1, parseInt(query.limit, 10) || DEFAULT_LIMIT));
  return { page, limit, skip: (page - 1) * limit };
}

async function getPerformanceSummary(prisma, query) {
  const range = resolvePerformanceRange(query);
  const societyId = query.societyId ? String(query.societyId) : null;
  const orders = await loadOrdersForRange(prisma, range, societyId);
  const truncated = orders.length > MAX_EXPORT_ROWS;
  const slice = truncated ? orders.slice(0, MAX_EXPORT_ROWS) : orders;
  const { summary, paymentStatusCounts, paymentMethodCounts } = aggregateOrders(slice);
  const patternSignals = computePatternSignals(slice);

  const failures = slice.filter((o) => TERMINAL_FAILURE_STATUSES.has(o.status)).length;
  const created = slice.length;

  return {
    dateRange: {
      preset: range.preset,
      from: range.fromYmd,
      to: range.toYmd,
      timezone: range.timezone,
      endInclusive: true,
    },
    filters: { societyId },
    summary: {
      ...summary,
      ordersCreated: created,
      cancelledOrRejected: failures,
      cancellationRate: created > 0 ? roundMoney(failures / created) : 0,
    },
    paymentStatusCounts,
    paymentMethodCounts,
    patternSignals,
    truncated,
    maxOrdersScanned: MAX_EXPORT_ROWS,
  };
}

async function getPerformanceLeaderboard(prisma, query) {
  const range = resolvePerformanceRange(query);
  const societyId = query.societyId ? String(query.societyId) : null;
  const { page, limit, skip } = parsePageLimit(query);
  const orders = await loadOrdersForRange(prisma, range, societyId);
  const slice = orders.slice(0, MAX_EXPORT_ROWS);
  const { bySeller } = aggregateOrders(slice);
  const rows = sortLeaderboard(
    [...bySeller.values()].map(serializeSellerRow),
    query.sort
  );
  return {
    dateRange: {
      preset: range.preset,
      from: range.fromYmd,
      to: range.toYmd,
      timezone: range.timezone,
    },
    sort: LEADERBOARD_SORT.has(query.sort) ? query.sort : DEFAULT_SORT,
    total: rows.length,
    page,
    limit,
    sellers: rows.slice(skip, skip + limit),
    truncated: orders.length > MAX_EXPORT_ROWS,
  };
}

async function getSellerPerformanceDetail(prisma, sellerId, query) {
  const range = resolvePerformanceRange(query);
  const orders = await prisma.order.findMany({
    where: {
      ...buildOrderWhere(range, query.societyId),
      items: { some: { listing: { sellerId } } },
    },
    select: orderSelect,
    orderBy: { createdAt: "desc" },
    take: MAX_EXPORT_ROWS,
  });

  const sellerOrder = orders.find((o) => sellerIdFromOrder(o) === sellerId);
  const seller =
    sellerOrder &&
    (sellerOrder.items || [])
      .map((i) => i.listing && i.listing.seller)
      .find((s) => s && s.id === sellerId);

  const { bySeller, paymentStatusCounts } = aggregateOrders(orders);
  const row = bySeller.get(sellerId);
  const buyerMix = await enrichBuyerNewRepeat(prisma, sellerId, orders, range);

  const statusCounts = {};
  for (const order of orders) {
    statusCounts[order.status] = (statusCounts[order.status] || 0) + 1;
  }

  return {
    dateRange: {
      preset: range.preset,
      from: range.fromYmd,
      to: range.toYmd,
      timezone: range.timezone,
    },
    seller: seller
      ? {
          id: seller.id,
          name: seller.name,
          phone: seller.phone,
          societyId: seller.societyId,
        }
      : { id: sellerId },
    metrics: row
      ? {
          ...serializeSellerRow(row),
          newBuyers: buyerMix.newBuyers,
          repeatBuyers: buyerMix.repeatBuyers,
        }
      : null,
    statusCounts,
    paymentStatusCounts,
    ordersCreated: orders.length,
    patternSignals: computeSellerPatternSignals(orders, sellerId),
  };
}

async function getSellerPerformanceOrders(prisma, sellerId, query) {
  const range = resolvePerformanceRange(query);
  const { page, limit, skip } = parsePageLimit(query);
  const where = {
    ...buildOrderWhere(range, query.societyId),
    items: { some: { listing: { sellerId } } },
  };

  const [orders, total] = await Promise.all([
    prisma.order.findMany({
      where,
      select: orderSelect,
      orderBy: { createdAt: "desc" },
      skip,
      take: limit,
    }),
    prisma.order.count({ where }),
  ]);

  return {
    page,
    limit,
    total,
    orders: orders.map((order) => ({
      id: order.id,
      orderNumber: order.orderNumber,
      status: order.status,
      type: order.type,
      createdAt: order.createdAt,
      completedAt: order.completedAt,
      buyer: order.buyer,
      grossFood: roundMoney(order.subtotal),
      netFood: roundMoney(
        Math.max(0, Number(order.subtotal || 0) - discountOnOrder(order))
      ),
      deliveryCharge: roundMoney(order.deliveryCharge),
      communityFee: roundMoney(order.communityFee),
      total: roundMoney(order.total),
      paymentMethod: order.paymentMethod,
      paymentStatus: order.paymentStatus,
      campaign: order.campaign,
      couponDiscount: roundMoney(discountOnOrder(order)),
    })),
  };
}

function aggregateCampaigns(orders) {
  const map = new Map();
  for (const order of orders) {
    if ((order.type || "regular") !== "pre_order" || !order.campaignId) continue;
    const key = order.campaignId;
    if (!map.has(key)) {
      map.set(key, {
        campaignId: key,
        title: order.campaign?.title || "Campaign",
        campaignStatus: order.campaign?.status || null,
        ordersPlaced: 0,
        completedOrders: 0,
        cancelledOrRejected: 0,
        grossFoodSales: 0,
        netFoodSales: 0,
      });
    }
    const row = map.get(key);
    row.ordersPlaced += 1;
    if (TERMINAL_FAILURE_STATUSES.has(order.status)) {
      row.cancelledOrRejected += 1;
    }
    if (order.status === QUALIFYING_SALES_STATUS) {
      row.completedOrders += 1;
      const discount = discountOnOrder(order);
      const gross = Number(order.subtotal || 0);
      row.grossFoodSales += gross;
      row.netFoodSales += Math.max(0, gross - discount);
    }
  }
  return [...map.values()].map((row) => ({
    ...row,
    grossFoodSales: roundMoney(row.grossFoodSales),
    netFoodSales: roundMoney(row.netFoodSales),
  }));
}

async function getCampaignPerformance(prisma, query) {
  const range = resolvePerformanceRange(query);
  const societyId = query.societyId ? String(query.societyId) : null;
  const orders = await prisma.order.findMany({
    where: {
      ...buildOrderWhere(range, societyId),
      type: "pre_order",
      campaignId: { not: null },
    },
    select: orderSelect,
    take: MAX_EXPORT_ROWS,
  });
  return {
    dateRange: {
      preset: range.preset,
      from: range.fromYmd,
      to: range.toYmd,
      timezone: range.timezone,
    },
    campaigns: aggregateCampaigns(orders),
  };
}

function buildCsv(rows) {
  const header = [
    "sellerId",
    "sellerName",
    "grossFoodSales",
    "netFoodSales",
    "deliveryCharges",
    "qualifyingOrders",
    "uniqueBuyers",
    "ordersCreated",
    "cancelledCount",
    "rejectedCount",
    "cancellationRate",
  ];
  const lines = [header.join(",")];
  for (const row of rows) {
    lines.push(
      [
        row.sellerId,
        `"${String(row.sellerName || "").replace(/"/g, '""')}"`,
        row.grossFoodSales,
        row.netFoodSales,
        row.deliveryCharges,
        row.qualifyingOrders,
        row.uniqueBuyers,
        row.ordersCreated,
        row.cancelledCount,
        row.rejectedCount,
        row.cancellationRate,
      ].join(",")
    );
  }
  return lines.join("\n");
}

async function getPerformanceExportCsv(prisma, query) {
  const range = resolvePerformanceRange(query);
  const societyId = query.societyId ? String(query.societyId) : null;
  const orders = await loadOrdersForRange(prisma, range, societyId);
  const slice = orders.slice(0, MAX_EXPORT_ROWS);
  const { bySeller } = aggregateOrders(slice);
  const rows = sortLeaderboard(
    [...bySeller.values()].map(serializeSellerRow),
    query.sort || DEFAULT_SORT
  );
  return buildCsv(rows);
}

module.exports = {
  aggregateOrders,
  computePatternSignals,
  resolvePerformanceRange,
  getPerformanceSummary,
  getPerformanceLeaderboard,
  getSellerPerformanceDetail,
  getSellerPerformanceOrders,
  getCampaignPerformance,
  getPerformanceExportCsv,
  QUALIFYING_SALES_STATUS,
};
