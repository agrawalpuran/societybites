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
    const timezoneAwareIso = /(?:Z|[+-]\d{2}:\d{2})$/i;
    if (!timezoneAwareIso.test(expectedReadyAt)) {
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

module.exports = { parseOptionalReadyAt };
