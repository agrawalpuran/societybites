const logger = require("./logger");
const { getLaunchCityConfig } = require("./launchCity");

const AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete";
const DETAILS_URL = "https://places.googleapis.com/v1/places";
const DETAILS_CACHE_TTL_MS = 10 * 60 * 1000;
const FETCH_TIMEOUT_MS = 8000;

const detailsCache = new Map();

function getApiKey() {
  return String(process.env.GOOGLE_PLACES_API_KEY || "").trim();
}

function isPlacesConfigured() {
  return Boolean(getApiKey());
}

function placesUnavailable() {
  const err = new Error("Society search is temporarily unavailable.");
  err.statusCode = 503;
  err.code = "PLACES_UNAVAILABLE";
  return err;
}

function abortTimeout(ms) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  return { signal: controller.signal, clear: () => clearTimeout(timer) };
}

async function googleFetch(url, { method = "GET", body } = {}) {
  const key = getApiKey();
  if (!key) throw placesUnavailable();

  const timeout = abortTimeout(FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method,
      signal: timeout.signal,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        "X-Goog-FieldMask":
          method === "GET"
            ? "id,displayName,formattedAddress,location,addressComponents"
            : "suggestions.placePrediction.placeId,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.text",
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });

    let json = null;
    try {
      json = await response.json();
    } catch (_) {
      json = null;
    }

    if (!response.ok) {
      logger.error("places", "Google Places request failed", {
        status: response.status,
        method,
      });
      throw placesUnavailable();
    }

    return json || {};
  } catch (err) {
    if (err.code === "PLACES_UNAVAILABLE") throw err;
    logger.error("places", "Google Places request error", {
      message: err && err.name,
    });
    throw placesUnavailable();
  } finally {
    timeout.clear();
  }
}

async function autocompletePlaces(query) {
  const launch = getLaunchCityConfig();
  const input = String(query || "").trim();
  const body = {
    input,
    languageCode: "en",
  };
  const region = String(
    process.env.GOOGLE_PLACES_REGION_CODE || launch.country || "IN"
  )
    .trim()
    .toUpperCase();
  if (/^[A-Z]{2}$/.test(region)) {
    body.includedRegionCodes = [region];
  }
  if (launch.bias) {
    body.locationBias = {
      circle: {
        center: {
          latitude: launch.bias.latitude,
          longitude: launch.bias.longitude,
        },
        radius: launch.bias.radiusMeters,
      },
    };
  }

  const json = await googleFetch(AUTOCOMPLETE_URL, {
    method: "POST",
    body,
  });
  return json;
}

async function getPlaceDetails(placeId) {
  const id = String(placeId || "")
    .trim()
    .replace(/^places\//, "");
  if (!id) {
    const err = new Error("We couldn't identify this society.");
    err.statusCode = 400;
    throw err;
  }

  const cached = detailsCache.get(id);
  if (cached && cached.expires > Date.now()) {
    return cached.data;
  }

  const json = await googleFetch(
    `${DETAILS_URL}/${encodeURIComponent(id)}?languageCode=en`
  );
  detailsCache.set(id, { data: json, expires: Date.now() + DETAILS_CACHE_TTL_MS });
  return json;
}

module.exports = {
  isPlacesConfigured,
  autocompletePlaces,
  getPlaceDetails,
  placesUnavailable,
};
