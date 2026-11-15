/**
 * Admin dashboard city scope (phase 1: dashboard + compare table).
 * Chips follow active serving cities from app settings.
 */
const { canonicalCityKey, listKnownCities } = require("./launchCity");
const {
  listServingCityRows,
  refreshServingCities,
} = require("./servingCities");
const { liveAccountWhere } = require("./accountDeletion");

const ORDER_WINDOW_DAYS = 7;

function httpError(statusCode, message, code) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (code) err.code = code;
  return err;
}

function parseAdminCityKeyQuery(query) {
  const raw = query && query.cityKey;
  if (raw === undefined || raw === null || raw === "") return null;
  const key = String(raw).trim().toLowerCase();
  if (!key || key === "all") return null;
  return key;
}

function groupSocietyIdsByCityKey(societies) {
  const map = new Map();
  for (const row of societies || []) {
    const cityKey = canonicalCityKey(row.city);
    if (!cityKey) continue;
    if (!map.has(cityKey)) map.set(cityKey, []);
    map.get(cityKey).push(row.id);
  }
  return map;
}

const SOCIETY_MAP_CACHE_MS = 30_000;
let societyMapCache = { at: 0, map: null };

async function loadSocietyIdsByCityKey(prisma) {
  const now = Date.now();
  if (societyMapCache.map && now - societyMapCache.at < SOCIETY_MAP_CACHE_MS) {
    return societyMapCache.map;
  }
  const societies = await prisma.society.findMany({
    select: { id: true, city: true },
  });
  const map = groupSocietyIdsByCityKey(societies);
  societyMapCache = { at: now, map };
  return map;
}

function clearSocietyCityMapCache() {
  societyMapCache = { at: 0, map: null };
}

/** `null` = all cities; `[]` = city selected but no societies yet. */
async function societyIdsForCityKey(prisma, cityKey) {
  if (!cityKey) return null;
  const map = await loadSocietyIdsByCityKey(prisma);
  return map.get(cityKey) || [];
}

function societyRecordWhere(societyIds) {
  return societyIdListWhere(societyIds);
}

async function resolvePerformanceSocietyFilter(prisma, query) {
  if (query && query.societyId) {
    return { mode: "single", societyId: String(query.societyId) };
  }
  const cityKey = await resolveAdminCityKey(query || {});
  if (!cityKey) return { mode: "all" };
  const societyIds = await societyIdsForCityKey(prisma, cityKey);
  return { mode: "city", cityKey, societyIds };
}

function reviewCityWhere(societyIds) {
  if (societyIds === null || societyIds === undefined) return {};
  if (!societyIds.length) {
    return { order: { societyId: { in: ["__none__"] } } };
  }
  return { order: { societyId: { in: societyIds } } };
}

function issueReporterCityWhere(societyIds) {
  if (societyIds === null || societyIds === undefined) return {};
  if (!societyIds.length) {
    return { user: { societyId: { in: ["__none__"] } } };
  }
  return { user: { societyId: { in: societyIds } } };
}

function mergeSocietyIdQuery(querySocietyId, citySocietyIds) {
  if (citySocietyIds === null || citySocietyIds === undefined) {
    return querySocietyId ? { societyId: String(querySocietyId) } : {};
  }
  if (querySocietyId) {
    const sid = String(querySocietyId);
    if (citySocietyIds.includes(sid)) {
      return { societyId: sid };
    }
    return { societyId: "__none__" };
  }
  return societyScopeWhere(citySocietyIds);
}

async function activeServingCityRows() {
  await refreshServingCities();
  return listServingCityRows().filter((row) => row.active);
}

async function resolveAdminCityKey(query) {
  const cityKey = parseAdminCityKeyQuery(query);
  if (!cityKey) return null;
  const active = await activeServingCityRows();
  const allowed = new Set(active.map((row) => row.cityKey));
  if (!allowed.has(cityKey)) {
    throw httpError(
      400,
      "City is not an active serving city",
      "INVALID_CITY_KEY"
    );
  }
  return cityKey;
}

function societyScopeWhere(societyIds) {
  if (societyIds === null || societyIds === undefined) return {};
  if (!societyIds.length) {
    return { societyId: { in: ["__none__"] } };
  }
  return { societyId: { in: societyIds } };
}

function societyIdListWhere(societyIds) {
  if (societyIds === null || societyIds === undefined) return {};
  if (!societyIds.length) return { id: { in: ["__none__"] } };
  return { id: { in: societyIds } };
}

async function orderStatsForWindow(prisma, scopedWhere, since) {
  const timeWhere = { createdAt: { gte: since }, ...scopedWhere };
  const [orders, pending, completed, cancelled, gmvAgg] = await Promise.all([
    prisma.order.count({ where: timeWhere }),
    prisma.order.count({ where: { ...timeWhere, status: "pending" } }),
    prisma.order.count({ where: { ...timeWhere, status: "completed" } }),
    prisma.order.count({ where: { ...timeWhere, status: "cancelled" } }),
    prisma.order.aggregate({
      where: { status: "completed", ...timeWhere },
      _sum: { subtotal: true },
    }),
  ]);
  return {
    orders,
    pending,
    completed,
    cancelled,
    foodGmv:
      Math.round((Number(gmvAgg._sum.subtotal) || 0) * 100) / 100,
  };
}

async function getAdminDashboardStats(prisma, { cityKey = null } = {}) {
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const since7d = new Date(
    Date.now() - ORDER_WINDOW_DAYS * 24 * 60 * 60 * 1000
  );

  let societyIds = null;
  let scope = { cityKey: null, displayName: null };
  if (cityKey) {
    const societies = await prisma.society.findMany({
      select: { id: true, city: true },
    });
    const byCity = groupSocietyIdsByCityKey(societies);
    societyIds = byCity.get(cityKey) || [];
    const entry = listKnownCities().find((c) => c.cityKey === cityKey);
    scope = {
      cityKey,
      displayName: entry ? entry.displayName : cityKey,
    };
  }

  const societyWhere = societyIdListWhere(societyIds);
  const scopedWhere = societyScopeWhere(societyIds);

  const userWhere = societyIds === null
    ? liveAccountWhere
    : { ...liveAccountWhere, ...scopedWhere };

  const reviewWhere =
    societyIds === null
      ? {}
      : { order: { societyId: { in: societyIds.length ? societyIds : ["__none__"] } } };

  const [
    totalUsers,
    totalSellers,
    totalBuyers,
    totalSocieties,
    activeListings,
    soldOutListings,
    totalOrders,
    todayOrders,
    pendingOrders,
    completedOrders,
    cancelledOrders,
    totalReviews,
    ratingAgg,
    completedFoodSalesAgg,
  ] = await Promise.all([
    prisma.user.count({ where: userWhere }),
    prisma.user.count({ where: { ...userWhere, role: "seller" } }),
    prisma.user.count({ where: { ...userWhere, role: "buyer" } }),
    societyIds === null
      ? prisma.society.count()
      : prisma.society.count({ where: societyWhere }),
    prisma.listing.count({
      where: { status: "active", ...scopedWhere },
    }),
    prisma.listing.count({
      where: { status: "sold_out", ...scopedWhere },
    }),
    prisma.order.count({ where: scopedWhere }),
    prisma.order.count({
      where: { createdAt: { gte: todayStart }, ...scopedWhere },
    }),
    prisma.order.count({ where: { status: "pending", ...scopedWhere } }),
    prisma.order.count({ where: { status: "completed", ...scopedWhere } }),
    prisma.order.count({ where: { status: "cancelled", ...scopedWhere } }),
    prisma.review.count({ where: reviewWhere }),
    prisma.review.aggregate({
      where: reviewWhere,
      _avg: { rating: true },
    }),
    prisma.order.aggregate({
      where: { status: "completed", ...scopedWhere },
      _sum: { subtotal: true },
    }),
  ]);

  const totalSales =
    Math.round((Number(completedFoodSalesAgg._sum.subtotal) || 0) * 100) / 100;

  const ordersRecent = await orderStatsForWindow(prisma, scopedWhere, since7d);

  return {
    scope,
    orderWindowDays: ORDER_WINDOW_DAYS,
    ordersRecent,
    totalUsers,
    totalSellers,
    totalBuyers,
    totalSocieties,
    activeListings,
    soldOutListings,
    totalOrders,
    todayOrders,
    pendingOrders,
    completedOrders,
    cancelledOrders,
    totalSales,
    totalReviews,
    avgPlatformRating: ratingAgg._avg.rating || 0,
  };
}

async function metricsForSocietyIds(prisma, societyIds, since) {
  const scopedWhere = societyScopeWhere(societyIds);
  const userWhere = {
    ...liveAccountWhere,
    role: "seller",
    ...scopedWhere,
  };

  const [societies, sellers, recent] = await Promise.all([
    societyIds === null
      ? prisma.society.count()
      : Promise.resolve(societyIds.length),
    prisma.user.count({ where: userWhere }),
    orderStatsForWindow(prisma, scopedWhere, since),
  ]);

  return {
    societies,
    sellers,
    orders7d: recent.orders,
    foodGmv7d: recent.foodGmv,
  };
}

async function getAdminDashboardCities(prisma) {
  const since = new Date(
    Date.now() - ORDER_WINDOW_DAYS * 24 * 60 * 60 * 1000
  );
  const activeRows = await activeServingCityRows();
  const societies = await prisma.society.findMany({
    select: { id: true, city: true },
  });
  const byCity = groupSocietyIdsByCityKey(societies);

  const rowStats = await Promise.all(
    activeRows.map(async (city) => {
      const ids = byCity.get(city.cityKey) || [];
      const metrics = await metricsForSocietyIds(prisma, ids, since);
      return {
        cityKey: city.cityKey,
        displayName: city.displayName,
        ...metrics,
      };
    })
  );

  const totals = await metricsForSocietyIds(prisma, null, since);

  return {
    activeCities: activeRows.map((row) => ({
      cityKey: row.cityKey,
      displayName: row.displayName,
    })),
    rows: rowStats,
    totals,
    periodDays: ORDER_WINDOW_DAYS,
  };
}

module.exports = {
  parseAdminCityKeyQuery,
  groupSocietyIdsByCityKey,
  resolveAdminCityKey,
  societyIdsForCityKey,
  societyRecordWhere,
  societyScopeWhere,
  resolvePerformanceSocietyFilter,
  mergeSocietyIdQuery,
  reviewCityWhere,
  issueReporterCityWhere,
  clearSocietyCityMapCache,
  getAdminDashboardStats,
  getAdminDashboardCities,
};