const { isMadeToOrderListing } = require("./listingAvailability");

const TIMEZONE_AWARE_ISO = /(?:Z|[+-]\d{2}:\d{2})$/i;

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

/**
 * Parse optional Ready-by fields for payment confirm.
 * Returns { omit: true } when neither field is sent.
 */
function parseOptionalReadyAt({ expectedReadyAt, readyInMinutes } = {}) {
  if (expectedReadyAt === undefined && readyInMinutes === undefined) {
    return { omit: true };
  }
  if (expectedReadyAt !== undefined && readyInMinutes !== undefined) {
    throw httpError(400, "Provide either readyInMinutes or expectedReadyAt, not both");
  }
  if (expectedReadyAt === null && readyInMinutes === undefined) {
    return { readyAt: null };
  }

  let readyAt;
  if (readyInMinutes !== undefined) {
    if (
      typeof readyInMinutes !== "number" ||
      !Number.isFinite(readyInMinutes) ||
      readyInMinutes <= 0 ||
      readyInMinutes > 60
    ) {
      throw httpError(400, "readyInMinutes must be a positive number no greater than 60");
    }
    readyAt = new Date(Date.now() + readyInMinutes * 60 * 1000);
  } else {
    if (typeof expectedReadyAt !== "string") {
      throw httpError(
        400,
        "expectedReadyAt is required (timezone-aware ISO datetime or null to clear)"
      );
    }
    if (!TIMEZONE_AWARE_ISO.test(expectedReadyAt)) {
      throw httpError(400, "expectedReadyAt must include a UTC or timezone offset");
    }
    readyAt = new Date(expectedReadyAt);
    if (Number.isNaN(readyAt.getTime())) {
      throw httpError(400, "expectedReadyAt must be a valid timezone-aware ISO datetime");
    }
  }

  if (readyAt <= new Date()) {
    throw httpError(400, "Ready by time must be in the future");
  }
  return { readyAt };
}

/**
 * Optional buyer "Need by" datetime on Made-to-Order orders.
 * Does not compare against seller lead time — the seller decides on accept.
 */
function parseRequestedReadyAt(value, { listings = [], orderType } = {}) {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (orderType === "pre_order") {
    throw httpError(400, "requestedReadyAt is not available for pre-order campaigns");
  }
  const hasMadeToOrder = listings.some((listing) => isMadeToOrderListing(listing));
  if (!hasMadeToOrder) {
    throw httpError(400, "requestedReadyAt can only be set for Made to Order orders");
  }
  if (typeof value !== "string") {
    throw httpError(400, "requestedReadyAt must be a timezone-aware ISO datetime");
  }
  if (!TIMEZONE_AWARE_ISO.test(value)) {
    throw httpError(400, "requestedReadyAt must include a UTC or timezone offset");
  }
  const readyAt = new Date(value);
  if (Number.isNaN(readyAt.getTime())) {
    throw httpError(400, "requestedReadyAt must be a valid timezone-aware ISO datetime");
  }
  if (readyAt <= new Date()) {
    throw httpError(400, "Need by time must be in the future");
  }
  return readyAt;
}

module.exports = { parseOptionalReadyAt, parseRequestedReadyAt };
