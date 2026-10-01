const {
  formatIstYmd,
  addDaysYmd,
  startOfIstDay,
} = require("./sellerInsights");

const TERMINAL_STATUSES = Object.freeze([
  "completed",
  "cancelled",
  "rejected",
]);

/**
 * Drives the My Kitchen attention badge. Regular orders are auto-accepted, so
 * waiting on "pending" alone would miss every order that still needs cooking.
 */
const NEEDS_SELLER_ACTION = Object.freeze(["pending", "accepted", "preparing"]);

const SCOPES = Object.freeze([
  "active",
  "older_active",
  "recent_past",
  "older",
]);
const DEFAULT_OLDER_LIMIT = 20;
const MAX_OLDER_LIMIT = 50;
const RECENT_PAST_DAYS = 7;

/**
 * A finished order holds its place in Active this long. Mirrors
 * BuyerOrderVisibility.recentTerminalWindow in the app so a seller and a buyer
 * looking at the same order agree on when it moves to Past.
 */
const RECENT_TERMINAL_WINDOW_MS = 24 * 60 * 60 * 1000;

function recentPastCutoff(now = new Date()) {
  const today = formatIstYmd(now);
  const fromYmd = addDaysYmd(today, -(RECENT_PAST_DAYS - 1));
  return startOfIstDay(fromYmd);
}

function recentTerminalCutoff(now = new Date()) {
  return new Date(now.getTime() - RECENT_TERMINAL_WINDOW_MS);
}

/**
 * Terminal orders that ended within the grace period. createdAt is not a
 * fallback here: an order with no end timestamp has no moment to count from.
 *
 * The `not: null` guards matter because this is also used under NOT. Without
 * them a null timestamp compares as unknown rather than false, and negating
 * unknown drops the row instead of keeping it.
 */
function justEndedWhere(since) {
  return {
    status: { in: [...TERMINAL_STATUSES] },
    OR: [
      { completedAt: { not: null, gte: since } },
      { cancelledAt: { not: null, gte: since } },
      { rejectedAt: { not: null, gte: since } },
    ],
  };
}

function sellerOrdersBaseWhere(sellerId, status) {
  return {
    items: {
      some: {
        listing: { sellerId },
      },
    },
    ...(status ? { status: String(status) } : {}),
  };
}

function recentPastEventWhere(cutoff) {
  return {
    OR: [
      { completedAt: { gte: cutoff } },
      { cancelledAt: { gte: cutoff } },
      { rejectedAt: { gte: cutoff } },
      {
        AND: [
          { completedAt: null },
          { cancelledAt: null },
          { rejectedAt: null },
          { createdAt: { gte: cutoff } },
        ],
      },
    ],
  };
}

function olderPastEventWhere(cutoff) {
  return {
    OR: [
      { completedAt: { lt: cutoff } },
      { cancelledAt: { lt: cutoff } },
      { rejectedAt: { lt: cutoff } },
      {
        AND: [
          { completedAt: null },
          { cancelledAt: null },
          { rejectedAt: null },
          { createdAt: { lt: cutoff } },
        ],
      },
    ],
  };
}

function parseScope(value) {
  const scope = String(value || "").trim();
  if (!SCOPES.includes(scope)) {
    const err = new Error(
      "scope must be one of: active, older_active, recent_past, older"
    );
    err.statusCode = 400;
    throw err;
  }
  return scope;
}

function parsePage(value) {
  const page = Number.parseInt(String(value || "1"), 10);
  if (!Number.isFinite(page) || page < 1) return 1;
  return page;
}

function parseLimit(value) {
  const limit = Number.parseInt(String(value || String(DEFAULT_OLDER_LIMIT)), 10);
  if (!Number.isFinite(limit) || limit < 1) return DEFAULT_OLDER_LIMIT;
  return Math.min(limit, MAX_OLDER_LIMIT);
}

function whereForScope({ sellerId, scope, status, cutoff, terminalSince }) {
  const base = sellerOrdersBaseWhere(sellerId, status);
  if (scope === "active") {
    return {
      AND: [
        base,
        {
          OR: [
            {
              AND: [
                { status: { notIn: [...TERMINAL_STATUSES] } },
                { createdAt: { gte: cutoff } },
              ],
            },
            justEndedWhere(terminalSince),
          ],
        },
      ],
    };
  }
  if (scope === "older_active") {
    return {
      AND: [
        base,
        { status: { notIn: [...TERMINAL_STATUSES] } },
        { createdAt: { lt: cutoff } },
      ],
    };
  }
  if (scope === "recent_past") {
    return {
      AND: [
        base,
        { status: { in: [...TERMINAL_STATUSES] } },
        recentPastEventWhere(cutoff),
        // Still in its Active grace period, so it must not appear in both.
        { NOT: justEndedWhere(terminalSince) },
      ],
    };
  }
  return {
    AND: [
      base,
      { status: { in: [...TERMINAL_STATUSES] } },
      olderPastEventWhere(cutoff),
    ],
  };
}

async function listSellerOrders(
  prisma,
  {
    sellerId,
    scope: rawScope,
    status,
    page: rawPage,
    limit: rawLimit,
    now = new Date(),
    include,
  }
) {
  const scope = parseScope(rawScope);
  const cutoff = recentPastCutoff(now);
  const terminalSince = recentTerminalCutoff(now);
  const where = whereForScope({ sellerId, scope, status, cutoff, terminalSince });
  const orderBy = { createdAt: "desc" };
  const paginated = scope === "older" || scope === "older_active";

  if (!paginated) {
    const extras = [];
    if (scope === "recent_past") {
      extras.push(
        prisma.order.findFirst({
          where: whereForScope({
            sellerId,
            scope: "older",
            status,
            cutoff,
            terminalSince,
          }),
          select: { id: true },
        })
      );
    } else {
      extras.push(
        prisma.order.findFirst({
          where: whereForScope({
            sellerId,
            scope: "older_active",
            status,
            cutoff,
            terminalSince,
          }),
          select: { id: true },
        })
      );
      extras.push(
        prisma.order.count({
          where: {
            ...sellerOrdersBaseWhere(sellerId, status),
            status: { in: NEEDS_SELLER_ACTION },
          },
        })
      );
    }

    const [orders, olderSample, pendingCount] = await Promise.all([
      prisma.order.findMany({
        where,
        include,
        orderBy,
      }),
      extras[0],
      extras[1] ?? Promise.resolve(0),
    ]);
    return {
      orders,
      hasMore: false,
      hasOlder: Boolean(olderSample),
      pendingCount: Number(pendingCount) || 0,
      scope,
    };
  }

  const page = parsePage(rawPage);
  const limit = parseLimit(rawLimit);
  const rows = await prisma.order.findMany({
    where,
    include,
    orderBy,
    skip: (page - 1) * limit,
    take: limit + 1,
  });
  const hasMore = rows.length > limit;
  return {
    orders: hasMore ? rows.slice(0, limit) : rows,
    hasMore,
    hasOlder: true,
    pendingCount: 0,
    scope,
    page,
    limit,
  };
}

module.exports = {
  TERMINAL_STATUSES,
  SCOPES,
  DEFAULT_OLDER_LIMIT,
  RECENT_PAST_DAYS,
  recentPastCutoff,
  parseScope,
  listSellerOrders,
};
