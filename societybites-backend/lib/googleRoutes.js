const logger = require("./logger");

/**
 * Optional Google Routes abstraction for road distance / duration.
 * Eligibility continues to use society coordinates + Haversine.
 * Not called from Explore Nearby. Missing credentials must not block checkout.
 */
function getRoutesApiKey() {
  return String(process.env.GOOGLE_ROUTES_API_KEY || process.env.GOOGLE_PLACES_API_KEY || "").trim();
}

function isRoutesConfigured() {
  return Boolean(getRoutesApiKey());
}

/**
 * @returns {Promise<{ distanceKm: number, durationMinutes: number }|null>}
 */
async function estimateRoadDistance() {
  if (!isRoutesConfigured()) return null;
  logger.info("routes", "Road-distance lookup skipped in Phase 5 MVP (optional display only)");
  return null;
}

module.exports = {
  isRoutesConfigured,
  estimateRoadDistance,
};
