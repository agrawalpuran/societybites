const IST = "Asia/Kolkata";
const YMD = /^\d{4}-\d{2}-\d{2}$/;
const QUALIFYING_SALES_STATUS = "completed";
const DEFAULT_PRESET = "last_7_days";
const MAX_RANGE_DAYS = 366;
const RECENT_LIMIT = 8;
const TOP_ITEMS_LIMIT = 8;

const PRESETS = new Set([
  "today",
  "last_7_days",
  "last_30_days",
  "this_month",
  "custom",
]);

function roundMoney(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function formatIstYmd(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: IST,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date instanceof Date ? date : new Date(date));
}

function addDaysYmd(ymd, days) {
  const [year, month, day] = String(ymd).split("-").map(Number);
  const utc = Date.UTC(year, month - 1, day + days);
  const dt = new Date(utc);
  const yy = dt.getUTCFullYear();
  const mm = String(dt.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(dt.getUTCDate()).padStart(2, "0");
  return `${yy}-${mm}-${dd}`;
}

function startOfIstDay(ymd) {
  return new Date(`${ymd}T00:00:00.000+05:30`);
}

function endOfIstDay(ymd) {
  return new Date(`${ymd}T23:59:59.999+05:30`);
}

function eachYmdInclusive(fromYmd, toYmd) {
  const days = [];
  let cursor = fromYmd;
  while (cursor <= toYmd) {
    days.push(cursor);
    cursor = addDaysYmd(cursor, 1);
    if (days.length > MAX_RANGE_DAYS) break;
  }
  return days;
}

function parseYmd(value, label) {
  const ymd = String(value || "").trim();
  if (!YMD.test(ymd)) {
    const err = new Error(`${label} must be YYYY-MM-DD`);
    err.statusCode = 400;
    throw err;
  }
  return ymd;
}

function resolveDateRange({ preset, from, to, now = new Date() } = {}) {
  const today = formatIstYmd(now);
  const rawPreset = String(preset || "").trim();
  const hasCustomDates = Boolean(from && to);
  let selected = rawPreset || (hasCustomDates ? "custom" : DEFAULT_PRESET);
  if (!PRESETS.has(selected)) {
    const err = new Error("Invalid date range preset");
    err.statusCode = 400;
    throw err;
  }

  let fromYmd;
  let toYmd;
  if (selected === "today") {
    fromYmd = today;
    toYmd = today;
  } else if (selected === "last_7_days") {
    toYmd = today;
    fromYmd = addDaysYmd(today, -6);
  } else if (selected === "last_30_days") {
    toYmd = today;
    fromYmd = addDaysYmd(today, -29);
  } else if (selected === "this_month") {
    toYmd = today;
    fromYmd = `${today.slice(0, 7)}-01`;
  } else {
    fromYmd = parseYmd(from, "from");
    toYmd = parseYmd(to, "to");
  }

  if (fromYmd > toYmd) {
    const err = new Error("from must be on or before to");
    err.statusCode = 400;
    throw err;
  }
  if (eachYmdInclusive(fromYmd, toYmd).length > MAX_RANGE_DAYS) {
    const err = new Error("Date range is too large");
    err.statusCode = 400;
    throw err;
  }

  return {
    preset: selected,
    fromYmd,
    toYmd,
    from: startOfIstDay(fromYmd),
    to: endOfIstDay(toYmd),
    timezone: IST,
    endInclusive: true,
  };
}

function sellerLineItems(order, sellerId) {
  return (order.items || []).filter(
    (item) => item.listing && item.listing.sellerId === sellerId
  );
}

function sellerAmount(order, sellerId) {
  return sellerLineItems(order, sellerId).reduce(
    (sum, item) => sum + Number(item.quantity || 0) * Number(item.unitPrice || 0),
    0
  );
}

function computeInsights({ orders, sellerId, range, lifetimeOrderCount = 0 }) {
  const list = Array.isArray(orders) ? orders : [];
  const days = eachYmdInclusive(range.fromYmd, range.toYmd);
  const dailyMap = {};
  for (const date of days) {
    dailyMap[date] = { date, orders: 0, sales: 0 };
  }

  const statusCounts = {};
  const itemMap = {};
  let sales = 0;
  let itemsSold = 0;
  let completedOrders = 0;

  for (const order of list) {
    const ymd = formatIstYmd(order.createdAt);
    statusCounts[order.status] = (statusCounts[order.status] || 0) + 1;
    if (dailyMap[ymd]) dailyMap[ymd].orders += 1;

    const lines = sellerLineItems(order, sellerId);
    if (order.status !== QUALIFYING_SALES_STATUS) continue;

    completedOrders += 1;
    const lineSales = lines.reduce(
      (sum, item) => sum + Number(item.quantity || 0) * Number(item.unitPrice || 0),
      0
    );
    const lineQty = lines.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
    sales += lineSales;
    itemsSold += lineQty;
    if (dailyMap[ymd]) dailyMap[ymd].sales = roundMoney(dailyMap[ymd].sales + lineSales);

    for (const item of lines) {
      const listingId = item.listingId || (item.listing && item.listing.id);
      if (!listingId) continue;
      if (!itemMap[listingId]) {
        itemMap[listingId] = {
          listingId,
          name: (item.listing && item.listing.name) || "Item",
          quantitySold: 0,
          sales: 0,
        };
      }
      itemMap[listingId].quantitySold += Number(item.quantity || 0);
      itemMap[listingId].sales = roundMoney(
        itemMap[listingId].sales + Number(item.quantity || 0) * Number(item.unitPrice || 0)
      );
    }
  }

  const statusBreakdown = Object.entries(statusCounts)
    .map(([status, count]) => ({ status, count }))
    .sort((a, b) => b.count - a.count || a.status.localeCompare(b.status));

  const topItems = Object.values(itemMap)
    .sort((a, b) => b.quantitySold - a.quantitySold || b.sales - a.sales)
    .slice(0, TOP_ITEMS_LIMIT);

  const recentOrders = list.slice(0, RECENT_LIMIT).map((order) => ({
    id: order.id,
    orderNumber: order.orderNumber || order.id,
    buyerName: (order.buyer && order.buyer.name) || "Neighbor",
    amount: roundMoney(sellerAmount(order, sellerId)),
    status: order.status,
    createdAt: order.createdAt,
  }));

  return {
    dateRange: {
      preset: range.preset,
      from: range.fromYmd,
      to: range.toYmd,
      timezone: range.timezone,
      endInclusive: true,
    },
    summary: {
      orders: list.length,
      sales: roundMoney(sales),
      itemsSold,
      averageOrderValue: completedOrders > 0 ? roundMoney(sales / completedOrders) : 0,
      completedOrders,
    },
    statusBreakdown,
    dailyTrend: days.map((date) => ({
      date,
      orders: dailyMap[date].orders,
      sales: roundMoney(dailyMap[date].sales),
    })),
    topItems,
    recentOrders,
    empty:
      lifetimeOrderCount === 0
        ? "none"
        : list.length === 0
          ? "period"
          : null,
  };
}

async function loadSellerInsights(prisma, { sellerId, preset, from, to, now } = {}) {
  const range = resolveDateRange({ preset, from, to, now });
  const sellerFilter = {
    items: { some: { listing: { sellerId } } },
  };

  const [orders, lifetimeOrderCount] = await Promise.all([
    prisma.order.findMany({
      where: {
        ...sellerFilter,
        createdAt: { gte: range.from, lte: range.to },
      },
      include: {
        buyer: { select: { name: true } },
        items: {
          include: {
            listing: { select: { id: true, name: true, sellerId: true } },
          },
        },
      },
      orderBy: { createdAt: "desc" },
    }),
    prisma.order.count({ where: sellerFilter }),
  ]);

  return computeInsights({ orders, sellerId, range, lifetimeOrderCount });
}

module.exports = {
  IST,
  QUALIFYING_SALES_STATUS,
  DEFAULT_PRESET,
  formatIstYmd,
  addDaysYmd,
  resolveDateRange,
  computeInsights,
  loadSellerInsights,
};
