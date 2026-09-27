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

const SCOPES = Object.freeze(["active", "recent_past", "older"]);
const DEFAULT_OLDER_LIMIT = 20;
const MAX_OLDER_LIMIT = 50;
const RECENT_PAST_DAYS = 7;

function recentPastCutoff(now = new Date()) {
  const today = formatIstYmd(now);
  const fromYmd = addDaysYmd(today, -(RECENT_PAST_DAYS - 1));
  return startOfIstDay(fromYmd);
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
      "scope must be one of: active, recent_past, older"
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

function whereForScope({ sellerId, scope, status, cutoff }) {
  const base = sellerOrdersBaseWhere(sellerId, status);
  if (scope === "active") {
    return {
      AND: [base, { status: { notIn: [...TERMINAL_STATUSES] } }],
    };
  }
  if (scope === "recent_past") {
    return {
      AND: [
        base,
        { status: { in: [...TERMINAL_STATUSES] } },
        recentPastEventWhere(cutoff),
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
  const where = whereForScope({ sellerId, scope, status, cutoff });
  const orderBy = { createdAt: "desc" };

  if (scope !== "older") {
    const [orders, olderSample] = await Promise.all([
      prisma.order.findMany({
        where,
        include,
        orderBy,
      }),
      scope === "recent_past"
        ? prisma.order.findFirst({
            where: whereForScope({
              sellerId,
              scope: "older",
              status,
              cutoff,
            }),
            select: { id: true },
          })
        : Promise.resolve(null),
    ]);
    return {
      orders,
      hasMore: false,
      hasOlder: Boolean(olderSample),
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
