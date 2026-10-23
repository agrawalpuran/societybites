const { money } = require("./coupons");

const MIN_PERCENT = 1;
const MAX_PERCENT = 90;
const DISCOUNT_KEYS = [
  "discountEnabled",
  "discountPercent",
  "discountStartsAt",
  "discountEndsAt",
];

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function regularPriceOf(listing) {
  return money(Number(listing && listing.price));
}

function parseEnabled(value) {
  if (value === undefined) return undefined;
  if (value === null) return false;
  if (typeof value === "boolean") return value;
  if (value === "true" || value === "yes" || value === "1" || value === 1) {
    return true;
  }
  if (value === "false" || value === "no" || value === "0" || value === 0) {
    return false;
  }
  throw httpError(400, "discountEnabled must be true or false");
}

function parsePercent(value, { required }) {
  if (value === undefined) return undefined;
  if (value === null || value === "") {
    if (required) {
      throw httpError(400, "discountPercent must be between 1 and 90");
    }
    return null;
  }
  const percent = Number(value);
  if (!Number.isFinite(percent) || percent < MIN_PERCENT || percent > MAX_PERCENT) {
    throw httpError(400, "discountPercent must be between 1 and 90");
  }
  return percent;
}

function parseInstant(value, field) {
  if (value === undefined) return undefined;
  if (value === null || value === "") return null;
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw httpError(400, `${field} must be a valid date`);
  }
  return date;
}

function assertWindow(startsAt, endsAt) {
  if (startsAt && endsAt && endsAt.getTime() < startsAt.getTime()) {
    throw httpError(400, "discountEndsAt must be on or after discountStartsAt");
  }
}

function hasDiscountWrite(body) {
  if (!body || typeof body !== "object") return false;
  return DISCOUNT_KEYS.some((key) => Object.prototype.hasOwnProperty.call(body, key));
}

function quoteListingPrice(listing, now = new Date()) {
  const regularPrice = regularPriceOf(listing);
  const enabled = Boolean(listing && listing.discountEnabled);
  const percent = Number(listing && listing.discountPercent);
  const percentOk =
    Number.isFinite(percent) && percent >= MIN_PERCENT && percent <= MAX_PERCENT;
  const startsAt = listing && listing.discountStartsAt
    ? new Date(listing.discountStartsAt)
    : null;
  const endsAt = listing && listing.discountEndsAt
    ? new Date(listing.discountEndsAt)
    : null;
  const nowMs = now.getTime();
  const started = !startsAt || Number.isNaN(startsAt.getTime()) || startsAt.getTime() <= nowMs;
  const notEnded = !endsAt || Number.isNaN(endsAt.getTime()) || endsAt.getTime() >= nowMs;
  const discountActive = enabled && percentOk && started && notEnded;
  return {
    regularPrice,
    effectivePrice: discountActive
      ? money(regularPrice * (1 - percent / 100))
      : regularPrice,
    discountActive,
    discountPercent: discountActive ? percent : null,
    configuredPercent: percentOk ? percent : null,
  };
}

function parseDiscountCreateFields(body = {}) {
  const enabled = parseEnabled(body.discountEnabled);
  const discountEnabled = enabled === undefined ? false : enabled;
  const discountPercent = parsePercent(body.discountPercent, {
    required: discountEnabled,
  });
  const discountStartsAt = parseInstant(body.discountStartsAt, "discountStartsAt");
  const discountEndsAt = parseInstant(body.discountEndsAt, "discountEndsAt");
  const startsAt = discountStartsAt === undefined ? null : discountStartsAt;
  const endsAt = discountEndsAt === undefined ? null : discountEndsAt;
  assertWindow(startsAt, endsAt);
  if (discountEnabled && (discountPercent === undefined || discountPercent == null)) {
    throw httpError(400, "discountPercent must be between 1 and 90");
  }
  return {
    discountEnabled,
    discountPercent: discountPercent === undefined ? null : discountPercent,
    discountStartsAt: startsAt,
    discountEndsAt: endsAt,
  };
}

function parseDiscountUpdateFields(body = {}, listing = {}) {
  if (!hasDiscountWrite(body)) return undefined;

  const nextEnabled = parseEnabled(body.discountEnabled);
  const discountEnabled =
    nextEnabled === undefined ? Boolean(listing.discountEnabled) : nextEnabled;

  let discountPercent;
  if (Object.prototype.hasOwnProperty.call(body, "discountPercent")) {
    discountPercent = parsePercent(body.discountPercent, { required: discountEnabled });
  } else {
    discountPercent = listing.discountPercent == null
      ? null
      : parsePercent(listing.discountPercent, { required: false });
  }

  const nextStart = Object.prototype.hasOwnProperty.call(body, "discountStartsAt")
    ? parseInstant(body.discountStartsAt, "discountStartsAt")
    : listing.discountStartsAt
      ? new Date(listing.discountStartsAt)
      : null;
  const nextEnd = Object.prototype.hasOwnProperty.call(body, "discountEndsAt")
    ? parseInstant(body.discountEndsAt, "discountEndsAt")
    : listing.discountEndsAt
      ? new Date(listing.discountEndsAt)
      : null;

  const startsAt = nextStart === undefined ? null : nextStart;
  const endsAt = nextEnd === undefined ? null : nextEnd;
  assertWindow(startsAt, endsAt);

  if (discountEnabled && (discountPercent === undefined || discountPercent == null)) {
    throw httpError(400, "discountPercent must be between 1 and 90");
  }

  return {
    discountEnabled,
    discountPercent: discountPercent === undefined ? null : discountPercent,
    discountStartsAt: startsAt,
    discountEndsAt: endsAt,
  };
}

function serializeListingDiscount(listing, now = new Date()) {
  const quote = quoteListingPrice(listing, now);
  return {
    effectivePrice: quote.effectivePrice,
    discountPercent: listing && listing.discountPercent != null
      ? Number(listing.discountPercent)
      : null,
    discountActive: quote.discountActive,
    discountEnabled: Boolean(listing && listing.discountEnabled),
    discountStartsAt: (listing && listing.discountStartsAt) || null,
    discountEndsAt: (listing && listing.discountEndsAt) || null,
  };
}

function orderItemDiscountSnapshot(listing, now = new Date()) {
  const quote = quoteListingPrice(listing, now);
  return {
    unitPrice: quote.effectivePrice,
    originalUnitPrice: quote.regularPrice,
    discountPercent: quote.discountActive ? quote.discountPercent : null,
  };
}

module.exports = {
  money,
  quoteListingPrice,
  parseDiscountCreateFields,
  parseDiscountUpdateFields,
  serializeListingDiscount,
  orderItemDiscountSnapshot,
  hasDiscountWrite,
  MIN_PERCENT,
  MAX_PERCENT,
};
