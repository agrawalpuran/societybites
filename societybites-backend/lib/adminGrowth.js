const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

const VALID_RANGES = new Set([
  "day",
  "week",
  "month",
  "quarter",
  "half_year",
  "year",
]);

function istParts(date) {
  const shifted = new Date(date.getTime() + IST_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth(),
    day: shifted.getUTCDate(),
    weekday: shifted.getUTCDay(),
  };
}

function startOfIstDay(date) {
  const parts = istParts(date);
  return new Date(Date.UTC(parts.year, parts.month, parts.day) - IST_OFFSET_MS);
}

function addIstDays(date, days) {
  return new Date(date.getTime() + days * 86400000);
}

function startOfIstWeek(date) {
  const parts = istParts(date);
  const daysSinceMonday = (parts.weekday + 6) % 7;
  return addIstDays(startOfIstDay(date), -daysSinceMonday);
}

function startOfIstMonth(date) {
  const parts = istParts(date);
  return new Date(Date.UTC(parts.year, parts.month, 1) - IST_OFFSET_MS);
}

function startOfIstQuarter(date) {
  const parts = istParts(date);
  const quarterMonth = Math.floor(parts.month / 3) * 3;
  return new Date(Date.UTC(parts.year, quarterMonth, 1) - IST_OFFSET_MS);
}

function startOfIstHalfYear(date) {
  const parts = istParts(date);
  const halfMonth = parts.month < 6 ? 0 : 6;
  return new Date(Date.UTC(parts.year, halfMonth, 1) - IST_OFFSET_MS);
}

function startOfIstYear(date) {
  const parts = istParts(date);
  return new Date(Date.UTC(parts.year, 0, 1) - IST_OFFSET_MS);
}

function formatDayLabel(start) {
  const parts = istParts(start);
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  return `${parts.day} ${months[parts.month]}`;
}

function formatMonthLabel(start) {
  const parts = istParts(start);
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  return `${months[parts.month]} ${parts.year}`;
}

function formatQuarterLabel(start) {
  const parts = istParts(start);
  const quarter = Math.floor(parts.month / 3) + 1;
  return `Q${quarter} ${parts.year}`;
}

function formatHalfYearLabel(start) {
  const parts = istParts(start);
  return parts.month < 6 ? `H1 ${parts.year}` : `H2 ${parts.year}`;
}

function formatWeekLabel(start) {
  const end = addIstDays(start, 6);
  return `${formatDayLabel(start)} – ${formatDayLabel(end)}`;
}

function buildBuckets(range, now = new Date()) {
  const buckets = [];

  if (range === "day") {
    const todayStart = startOfIstDay(now);
    for (let i = 13; i >= 0; i -= 1) {
      const start = addIstDays(todayStart, -i);
      const end = addIstDays(start, 1);
      buckets.push({ start, end, label: formatDayLabel(start) });
    }
    return buckets;
  }

  if (range === "week") {
    const thisWeek = startOfIstWeek(now);
    for (let i = 7; i >= 0; i -= 1) {
      const start = addIstDays(thisWeek, -i * 7);
      const end = addIstDays(start, 7);
      buckets.push({ start, end, label: formatWeekLabel(start) });
    }
    return buckets;
  }

  if (range === "month") {
    let cursor = startOfIstMonth(now);
    for (let i = 5; i >= 0; i -= 1) {
      const parts = istParts(cursor);
      const start = new Date(
        Date.UTC(parts.year, parts.month - i, 1) - IST_OFFSET_MS
      );
      const endParts = istParts(start);
      const end = new Date(
        Date.UTC(endParts.year, endParts.month + 1, 1) - IST_OFFSET_MS
      );
      buckets.push({ start, end, label: formatMonthLabel(start) });
    }
    return buckets;
  }

  if (range === "quarter") {
    let cursor = startOfIstQuarter(now);
    for (let i = 3; i >= 0; i -= 1) {
      const parts = istParts(cursor);
      const month = parts.month - i * 3;
      const year = parts.year + Math.floor(month / 12);
      const normalizedMonth = ((month % 12) + 12) % 12;
      const start = new Date(
        Date.UTC(year, normalizedMonth, 1) - IST_OFFSET_MS
      );
      const end = new Date(
        Date.UTC(year, normalizedMonth + 3, 1) - IST_OFFSET_MS
      );
      buckets.push({ start, end, label: formatQuarterLabel(start) });
    }
    return buckets;
  }

  if (range === "half_year") {
    let cursor = startOfIstHalfYear(now);
    for (let i = 3; i >= 0; i -= 1) {
      const parts = istParts(cursor);
      const month = parts.month - i * 6;
      const year = parts.year + Math.floor(month / 12);
      const normalizedMonth = ((month % 12) + 12) % 12;
      const start = new Date(
        Date.UTC(year, normalizedMonth, 1) - IST_OFFSET_MS
      );
      const end = new Date(
        Date.UTC(year, normalizedMonth + 6, 1) - IST_OFFSET_MS
      );
      buckets.push({ start, end, label: formatHalfYearLabel(start) });
    }
    return buckets;
  }

  // year — last 12 calendar months including current
  const monthStart = startOfIstMonth(now);
  for (let i = 11; i >= 0; i -= 1) {
    const parts = istParts(monthStart);
    const start = new Date(
      Date.UTC(parts.year, parts.month - i, 1) - IST_OFFSET_MS
    );
    const endParts = istParts(start);
    const end = new Date(
      Date.UTC(endParts.year, endParts.month + 1, 1) - IST_OFFSET_MS
    );
    buckets.push({ start, end, label: formatMonthLabel(start) });
  }
  return buckets;
}

const ACCOUNT_WHERE_BASE = {
  suspended: false,
  role: { not: "super_admin" },
};

async function countGrowthForWindow(prisma, start, end) {
  const [newAccounts, newBuyers, newSellers] = await Promise.all([
    prisma.user.count({
      where: {
        ...ACCOUNT_WHERE_BASE,
        createdAt: { gte: start, lt: end },
      },
    }),
    prisma.user.count({
      where: {
        suspended: false,
        role: "buyer",
        createdAt: { gte: start, lt: end },
      },
    }),
    prisma.sellerTermsAcceptance.count({
      where: {
        acceptedAt: { gte: start, lt: end },
      },
    }),
  ]);
  return { newAccounts, newBuyers, newSellers };
}

async function getAdminGrowth(prisma, range, now = new Date()) {
  const buckets = buildBuckets(range, now);
  if (buckets.length === 0) {
    return {
      range,
      timezone: "Asia/Kolkata",
      start: null,
      end: now.toISOString(),
      summary: { newAccounts: 0, newBuyers: 0, newSellers: 0 },
      series: [],
    };
  }

  const rangeStart = buckets[0].start;
  const rangeEnd = buckets[buckets.length - 1].end;

  const series = [];
  for (const bucket of buckets) {
    const counts = await countGrowthForWindow(
      prisma,
      bucket.start,
      bucket.end
    );
    series.push({
      label: bucket.label,
      start: bucket.start.toISOString(),
      end: bucket.end.toISOString(),
      ...counts,
    });
  }

  const summary = await countGrowthForWindow(prisma, rangeStart, rangeEnd);

  // Latest period first (e.g. today on top for daily view).
  series.reverse();

  return {
    range,
    timezone: "Asia/Kolkata",
    start: rangeStart.toISOString(),
    end: rangeEnd.toISOString(),
    summary,
    series,
  };
}

function normalizeGrowthRange(raw) {
  const value = String(raw || "week").trim().toLowerCase();
  if (!VALID_RANGES.has(value)) return null;
  return value;
}

const VALID_METRICS = new Set(["accounts", "buyers", "sellers"]);
const MEMBERS_LIMIT = 200;
const MAX_WINDOW_MS = 366 * 86400000;

const USER_CONTACT_SELECT = {
  id: true,
  name: true,
  phone: true,
  role: true,
  createdAt: true,
  suspended: true,
  society: { select: { name: true, city: true } },
};

function normalizeGrowthMetric(raw) {
  const value = String(raw || "").trim().toLowerCase();
  if (!VALID_METRICS.has(value)) return null;
  return value;
}

function parseGrowthWindow(startRaw, endRaw) {
  const start = new Date(String(startRaw || ""));
  const end = new Date(String(endRaw || ""));
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    return null;
  }
  if (end <= start) return null;
  if (end.getTime() - start.getTime() > MAX_WINDOW_MS) return null;
  return { start, end };
}

function mapUserContact(user, eventAt, { includeSociety = false } = {}) {
  const base = {
    id: user.id,
    name: user.name,
    phone: user.phone,
    role: user.role,
    eventAt: eventAt.toISOString(),
  };
  if (!includeSociety) return base;
  const societyName = user.society?.name?.trim() || null;
  const societyCity = user.society?.city?.trim() || null;
  return {
    ...base,
    societyName,
    societyCity,
  };
}

async function listAdminGrowthMembers(prisma, metric, start, end) {
  if (metric === "accounts") {
    const users = await prisma.user.findMany({
      where: {
        ...ACCOUNT_WHERE_BASE,
        createdAt: { gte: start, lt: end },
      },
      select: USER_CONTACT_SELECT,
      orderBy: { createdAt: "desc" },
      take: MEMBERS_LIMIT,
    });
    return users.map((u) =>
      mapUserContact(u, u.createdAt, { includeSociety: true })
    );
  }

  if (metric === "buyers") {
    const users = await prisma.user.findMany({
      where: {
        suspended: false,
        role: "buyer",
        createdAt: { gte: start, lt: end },
      },
      select: USER_CONTACT_SELECT,
      orderBy: { createdAt: "desc" },
      take: MEMBERS_LIMIT,
    });
    return users.map((u) =>
      mapUserContact(u, u.createdAt, { includeSociety: true })
    );
  }

  const acceptances = await prisma.sellerTermsAcceptance.findMany({
    where: { acceptedAt: { gte: start, lt: end } },
    include: { user: { select: USER_CONTACT_SELECT } },
    orderBy: { acceptedAt: "desc" },
    take: MEMBERS_LIMIT * 3,
  });

  const seen = new Set();
  const members = [];
  for (const row of acceptances) {
    const user = row.user;
    if (!user || user.role === "super_admin" || seen.has(user.id)) continue;
    seen.add(user.id);
    members.push(
      mapUserContact(user, row.acceptedAt, { includeSociety: true })
    );
    if (members.length >= MEMBERS_LIMIT) break;
  }
  return members;
}

module.exports = {
  VALID_RANGES,
  VALID_METRICS,
  normalizeGrowthRange,
  normalizeGrowthMetric,
  parseGrowthWindow,
  getAdminGrowth,
  listAdminGrowthMembers,
};
