const IST = "Asia/Kolkata";
const WEEKDAY_SHORT = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const COUNTED_ORDER_STATUSES = [
  "pending",
  "accepted",
  "preparing",
  "ready",
  "picked_up",
  "completed",
];

const clearedRecurringFields = Object.freeze({
  recurringEnabled: false,
  recurringWeekdays: [],
  recurringStartMinute: null,
  recurringEndMinute: null,
  recurringDailyLimit: null,
});

function httpError(message, statusCode = 400, code) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (code) err.code = code;
  return err;
}

function isRegularReadyNowListing(listing) {
  return Boolean(
    listing &&
      (listing.catalogType || "REGULAR") !== "PREORDER" &&
      !listing.campaignId &&
      (listing.availabilityMode || "READY_NOW") === "READY_NOW"
  );
}

function isRecurringReadyNowListing(listing) {
  return isRegularReadyNowListing(listing) && listing.recurringEnabled === true;
}

function parseWeekdays(value) {
  if (!Array.isArray(value) || value.length === 0) {
    throw httpError("Select at least one available day");
  }
  const days = [
    ...new Set(
      value.map((item) => parseInt(item, 10)).filter((n) => Number.isInteger(n))
    ),
  ].sort((a, b) => a - b);
  if (days.some((n) => n < 1 || n > 7) || days.length === 0) {
    throw httpError("Available days must be Monday (1) through Sunday (7)");
  }
  return days;
}

function parseMinuteOfDay(value, label) {
  const n = parseInt(value, 10);
  if (!Number.isFinite(n) || n < 0 || n > 1439) {
    throw httpError(`${label} must be a valid time`);
  }
  return n;
}

function parseDailyLimit(value) {
  if (value == null || value === "") return null;
  const n = parseInt(value, 10);
  if (!Number.isFinite(n) || n < 1 || n > 9999) {
    throw httpError("Daily quantity must be a positive number");
  }
  return n;
}

function isRecurringPayloadEnabled(body = {}) {
  return body.recurringEnabled === true || body.recurringEnabled === "true";
}

function hasRecurringPayload(body = {}) {
  return (
    body.recurringEnabled !== undefined ||
    body.recurringWeekdays !== undefined ||
    body.recurringStartMinute !== undefined ||
    body.recurringEndMinute !== undefined ||
    body.recurringDailyLimit !== undefined
  );
}

function recurringWriteFields(body, { catalogType, availabilityMode } = {}) {
  const enabled = isRecurringPayloadEnabled(body);
  const preorder = (catalogType || "REGULAR") === "PREORDER";
  const madeToOrder = (availabilityMode || "READY_NOW") === "MADE_TO_ORDER";

  if (enabled && preorder) {
    throw httpError("Pre-order listings cannot use a repeat schedule");
  }
  if (enabled && madeToOrder) {
    throw httpError("Made to order listings cannot use a repeat schedule");
  }
  if (preorder || madeToOrder) {
    return { ...clearedRecurringFields };
  }
  if (!enabled) {
    return { ...clearedRecurringFields };
  }

  const weekdays = parseWeekdays(body.recurringWeekdays);
  const start = parseMinuteOfDay(body.recurringStartMinute, "Start time");
  const end = parseMinuteOfDay(body.recurringEndMinute, "End time");
  if (end <= start) {
    throw httpError("End time must be after the start time");
  }

  return {
    recurringEnabled: true,
    recurringWeekdays: weekdays,
    recurringStartMinute: start,
    recurringEndMinute: end,
    recurringDailyLimit: parseDailyLimit(body.recurringDailyLimit),
  };
}

function recurringUpdateFields(body, listing, nextAvailabilityMode) {
  const mode = nextAvailabilityMode || listing.availabilityMode || "READY_NOW";
  const catalogType = listing.catalogType || "REGULAR";
  if (catalogType === "PREORDER" || mode === "MADE_TO_ORDER") {
    if (isRecurringPayloadEnabled(body)) {
      throw httpError(
        catalogType === "PREORDER"
          ? "Pre-order listings cannot use a repeat schedule"
          : "Made to order listings cannot use a repeat schedule"
      );
    }
    return { ...clearedRecurringFields };
  }
  if (!hasRecurringPayload(body)) return undefined;
  return recurringWriteFields(body, { catalogType, availabilityMode: mode });
}

function formatIstYmd(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: IST,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date instanceof Date ? date : new Date(date));
}

function istClock(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: IST,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now instanceof Date ? now : new Date(now));
  const get = (type) => parts.find((part) => part.type === type)?.value;
  const weekdayMap = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };
  const weekday = weekdayMap[get("weekday")] || 1;
  const hour = parseInt(get("hour"), 10) || 0;
  const minute = parseInt(get("minute"), 10) || 0;
  return {
    weekday,
    minuteOfDay: hour * 60 + minute,
    ymd: formatIstYmd(now),
  };
}

function startOfIstDay(ymd) {
  return new Date(`${ymd}T00:00:00.000+05:30`);
}

function endOfIstDay(ymd) {
  return new Date(`${ymd}T23:59:59.999+05:30`);
}

function formatClock(minuteOfDay) {
  const safe = Math.max(0, Math.min(1439, Number(minuteOfDay) || 0));
  const hour24 = Math.floor(safe / 60);
  const minute = safe % 60;
  const ampm = hour24 >= 12 ? "PM" : "AM";
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  return `${hour12}:${String(minute).padStart(2, "0")} ${ampm}`;
}

function formatWeekdaysSummary(weekdays) {
  const days = [...new Set((weekdays || []).map(Number))]
    .filter((n) => n >= 1 && n <= 7)
    .sort((a, b) => a - b);
  if (days.length === 0) return "";
  if (days.length === 7) return "Every day";
  const labels = days.map((n) => WEEKDAY_SHORT[n - 1]);
  const consecutive =
    days.length > 1 && days.every((n, i) => i === 0 || n === days[i - 1] + 1);
  if (consecutive && days.length >= 3) {
    return `${labels[0]}–${labels[labels.length - 1]}`;
  }
  return labels.join(", ");
}

function addDaysYmd(ymd, days) {
  const [year, month, day] = String(ymd).split("-").map(Number);
  const dt = new Date(Date.UTC(year, month - 1, day + days));
  const yy = dt.getUTCFullYear();
  const mm = String(dt.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(dt.getUTCDate()).padStart(2, "0");
  return `${yy}-${mm}-${dd}`;
}

function weekdayForYmd(ymd) {
  return istClock(startOfIstDay(ymd)).weekday;
}

function nextScheduledYmd(weekdays, fromYmd, fromMinute, startMinute, includeToday) {
  const days = [...new Set((weekdays || []).map(Number))].filter(
    (n) => n >= 1 && n <= 7
  );
  if (!days.length) return null;
  for (let offset = includeToday ? 0 : 1; offset <= 7; offset += 1) {
    const ymd = addDaysYmd(fromYmd, offset);
    const weekday = weekdayForYmd(ymd);
    if (!days.includes(weekday)) continue;
    if (offset === 0 && includeToday && fromMinute >= startMinute) continue;
    return ymd;
  }
  return null;
}

function nextAvailableLabel({ weekdays, startMinute, clock }) {
  const todayIsScheduled = (weekdays || []).includes(clock.weekday);
  if (todayIsScheduled && clock.minuteOfDay < startMinute) {
    return `Available today from ${formatClock(startMinute)}`;
  }
  const nextYmd = nextScheduledYmd(
    weekdays,
    clock.ymd,
    clock.minuteOfDay,
    startMinute,
    false
  );
  if (!nextYmd) return "";
  const tomorrow = addDaysYmd(clock.ymd, 1);
  if (nextYmd === tomorrow) {
    return `Available tomorrow from ${formatClock(startMinute)}`;
  }
  const label = WEEKDAY_SHORT[weekdayForYmd(nextYmd) - 1];
  return `Available ${label} from ${formatClock(startMinute)}`;
}

function evaluateRecurringAvailability(listing, { now = new Date(), soldToday = 0 } = {}) {
  const empty = {
    recurringEnabled: false,
    recurringUnavailable: false,
    recurringSoldOutToday: false,
    recurringBuyerLabel: "",
    recurringNextLabel: "",
    recurringScheduleSummary: "",
    recurringHoursSummary: "",
    recurringDailyLimitLabel: "",
  };
  if (!isRecurringReadyNowListing(listing)) return empty;

  const weekdays = listing.recurringWeekdays || [];
  const start = listing.recurringStartMinute;
  const end = listing.recurringEndMinute;
  const limit = listing.recurringDailyLimit;
  const clock = istClock(now);
  const paused = listing.status === "paused";
  const onDay = weekdays.includes(clock.weekday);
  const inHours =
    Number.isInteger(start) &&
    Number.isInteger(end) &&
    clock.minuteOfDay >= start &&
    clock.minuteOfDay < end;
  const soldOut =
    Number.isInteger(limit) && Number(soldToday) >= limit;
  const unavailable = paused || !onDay || !inHours || soldOut;

  let buyerLabel = `Available today · Until ${formatClock(end)}`;
  if (paused) buyerLabel = "Temporarily not available";
  else if (soldOut) buyerLabel = "Temporarily not available";
  else if (!onDay || !inHours) buyerLabel = "Temporarily not available";

  let nextLabel = "";
  if (soldOut && onDay) nextLabel = "Sold out for today";
  else if (unavailable && !paused) {
    nextLabel = nextAvailableLabel({
      weekdays,
      startMinute: start,
      clock,
    });
  }

  const limitLabel =
    Number.isInteger(limit) && limit > 0 ? `${limit}/day` : "";

  return {
    recurringEnabled: true,
    recurringUnavailable: unavailable,
    recurringSoldOutToday: soldOut,
    recurringBuyerLabel: buyerLabel,
    recurringNextLabel: nextLabel,
    recurringScheduleSummary: formatWeekdaysSummary(weekdays),
    recurringHoursSummary:
      Number.isInteger(start) && Number.isInteger(end)
        ? `${formatClock(start)} – ${formatClock(end)}`
        : "",
    recurringDailyLimitLabel: limitLabel,
  };
}

function remainingToday(limit, soldToday) {
  if (!Number.isInteger(limit)) return null;
  return Math.max(0, limit - Number(soldToday || 0));
}

async function countRecurringSoldToday(prisma, listingIds, now = new Date()) {
  const ids = [...new Set((listingIds || []).filter(Boolean))];
  if (!ids.length) return {};
  const clock = istClock(now);
  const grouped = await prisma.orderItem.groupBy({
    by: ["listingId"],
    where: {
      listingId: { in: ids },
      order: {
        status: { in: COUNTED_ORDER_STATUSES },
        createdAt: {
          gte: startOfIstDay(clock.ymd),
          lte: endOfIstDay(clock.ymd),
        },
      },
    },
    _sum: { quantity: true },
  });
  return Object.fromEntries(
    grouped.map((row) => [row.listingId, Number(row._sum && row._sum.quantity) || 0])
  );
}

async function attachRecurringAvailability(prisma, listings, now = new Date()) {
  const list = Array.isArray(listings) ? listings : [];
  const limited = list.filter(
    (listing) =>
      isRecurringReadyNowListing(listing) && listing.recurringDailyLimit != null
  );
  const soldByListing = limited.length
    ? await countRecurringSoldToday(
        prisma,
        limited.map((listing) => listing.id),
        now
      )
    : {};

  return list.map((listing) => {
    const soldToday = soldByListing[listing.id] || listing.recurringSoldToday || 0;
    const evaluated = evaluateRecurringAvailability(listing, { now, soldToday });
    return {
      ...listing,
      ...evaluated,
      recurringSoldToday: soldToday,
    };
  });
}

async function assertRecurringOrderable(prisma, listing, quantity, now = new Date()) {
  if (!isRecurringReadyNowListing(listing)) return;
  if (listing.status === "paused") {
    throw httpError(`"${listing.name}" is paused and cannot be ordered`);
  }

  const clock = istClock(now);
  const onDay = (listing.recurringWeekdays || []).includes(clock.weekday);
  const inHours =
    clock.minuteOfDay >= listing.recurringStartMinute &&
    clock.minuteOfDay < listing.recurringEndMinute;
  if (!onDay || !inHours) {
    throw httpError(
      `"${listing.name}" is temporarily not available`,
      400,
      "RECURRING_UNAVAILABLE"
    );
  }

  const limit = listing.recurringDailyLimit;
  if (!Number.isInteger(limit)) return;
  const soldMap = await countRecurringSoldToday(prisma, [listing.id], now);
  const soldToday = soldMap[listing.id] || 0;
  if (soldToday + quantity > limit) {
    throw httpError(
      soldToday >= limit
        ? `"${listing.name}" is sold out for today`
        : `Only ${Math.max(0, limit - soldToday)} portions are available for "${listing.name}" today.`,
      409,
      "RECURRING_DAILY_LIMIT"
    );
  }
}

module.exports = {
  IST,
  clearedRecurringFields,
  isRegularReadyNowListing,
  isRecurringReadyNowListing,
  recurringWriteFields,
  recurringUpdateFields,
  evaluateRecurringAvailability,
  attachRecurringAvailability,
  assertRecurringOrderable,
  formatClock,
  formatWeekdaysSummary,
  istClock,
  remainingToday,
};
