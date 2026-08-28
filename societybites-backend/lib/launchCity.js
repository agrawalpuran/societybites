/**
 * Launch-city configuration for society discovery.
 * One active city for now; aliases/bias maps are keyed so more cities can be
 * marked active later without changing the onboarding flow.
 */

const CITY_ALIASES = {
  bengaluru: [
    "bengaluru",
    "bangalore",
    "bengaluruurban",
    "bangaloreurban",
    "bengalururural",
    "bangalorerural",
  ],
  pune: ["pune", "pimprichinchwad"],
  hyderabad: ["hyderabad", "secunderabad"],
  mumbai: ["mumbai", "bombay", "navimumbai"],
  delhi: ["delhi", "newdelhi", "nctofdelhi"],
  chennai: ["chennai", "madras"],
};

const CITY_BIAS = {
  bengaluru: { latitude: 12.9716, longitude: 77.5946, radiusMeters: 40000 },
  pune: { latitude: 18.5204, longitude: 73.8567, radiusMeters: 35000 },
  hyderabad: { latitude: 17.385, longitude: 78.4867, radiusMeters: 35000 },
  mumbai: { latitude: 19.076, longitude: 72.8777, radiusMeters: 35000 },
  delhi: { latitude: 28.6139, longitude: 77.209, radiusMeters: 35000 },
  chennai: { latitude: 13.0827, longitude: 80.2707, radiusMeters: 35000 },
};

function httpError(statusCode, message, code) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (code) err.code = code;
  return err;
}

function normalizeCityKey(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function canonicalCityKey(value) {
  const key = normalizeCityKey(value);
  if (!key) return "";
  if (CITY_ALIASES[key]) return key;
  for (const [canonical, aliases] of Object.entries(CITY_ALIASES)) {
    if (aliases.includes(key)) return canonical;
  }
  return key;
}

function aliasesForCity(cityName) {
  const canonical = canonicalCityKey(cityName);
  return CITY_ALIASES[canonical] || (canonical ? [canonical] : []);
}

function getLaunchCityConfig() {
  const city = String(process.env.SOCIETY_LAUNCH_CITY || "Bengaluru").trim() || "Bengaluru";
  const state = String(process.env.SOCIETY_LAUNCH_STATE || "Karnataka").trim() || "Karnataka";
  const country = String(process.env.SOCIETY_LAUNCH_COUNTRY || "IN")
    .trim()
    .toUpperCase() || "IN";
  const canonical = canonicalCityKey(city);
  const lat = Number(process.env.SOCIETY_LAUNCH_LAT);
  const lng = Number(process.env.SOCIETY_LAUNCH_LNG);
  const radius = Number(process.env.SOCIETY_LAUNCH_RADIUS_M);
  const mapped = CITY_BIAS[canonical];
  const bias =
    Number.isFinite(lat) && Number.isFinite(lng)
      ? {
          latitude: lat,
          longitude: lng,
          radiusMeters: Number.isFinite(radius) && radius > 0 ? radius : 40000,
        }
      : mapped || null;

  return {
    city,
    state,
    country,
    canonical,
    aliases: aliasesForCity(city),
    bias,
  };
}

function isLaunchCityName(value, config = getLaunchCityConfig()) {
  const key = normalizeCityKey(value);
  if (!key) return false;
  return config.aliases.includes(key);
}

function isKnownNonLaunchCity(value, config = getLaunchCityConfig()) {
  const canonical = canonicalCityKey(value);
  if (!canonical) return false;
  if (canonical === config.canonical) return false;
  return Boolean(CITY_ALIASES[canonical]);
}

function splitAddressSegments(text) {
  return String(text || "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

function suggestionMatchesLaunchCity(suggestion, config = getLaunchCityConfig()) {
  const segments = [
    ...splitAddressSegments(suggestion && suggestion.address),
    ...splitAddressSegments(suggestion && suggestion.name),
  ];
  let sawLaunchCity = false;
  for (const segment of segments) {
    if (isLaunchCityName(segment, config)) sawLaunchCity = true;
    if (isKnownNonLaunchCity(segment, config)) return false;
  }
  return sawLaunchCity;
}

function societyMatchesLaunchCity(society, config = getLaunchCityConfig()) {
  const city = society && society.city;
  const state = society && society.state;
  if (isKnownNonLaunchCity(city, config)) return false;
  if (isLaunchCityName(city, config)) return true;
  const segments = splitAddressSegments(society && society.address);
  for (const segment of segments) {
    if (isKnownNonLaunchCity(segment, config)) return false;
    if (isLaunchCityName(segment, config)) return true;
  }
  if (state && normalizeCityKey(state) === normalizeCityKey(config.state)) {
    return isLaunchCityName(city, config);
  }
  return false;
}

function placeMatchesLaunchCity(place, config = getLaunchCityConfig()) {
  const candidates = [place && place.city, place && place.district];
  if (candidates.some((value) => isKnownNonLaunchCity(value, config))) {
    return false;
  }
  if (candidates.some((value) => isLaunchCityName(value, config))) {
    return true;
  }
  const segments = splitAddressSegments(place && place.address);
  for (const segment of segments) {
    if (isKnownNonLaunchCity(segment, config)) return false;
    if (isLaunchCityName(segment, config)) return true;
  }
  return false;
}

function launchCityUnavailableError(config = getLaunchCityConfig()) {
  return httpError(
    400,
    `This society is not currently available in SocietyBites. We are currently available in ${config.city}.`,
    "LAUNCH_CITY_UNAVAILABLE"
  );
}

function assertPlaceAllowedForLaunch(place, config = getLaunchCityConfig()) {
  const city = place && String(place.city || "").trim();
  const district = place && String(place.district || "").trim();
  if (!city && !district) {
    const err = new Error(
      "We couldn't confirm this society's city. Please try a different result."
    );
    err.statusCode = 400;
    err.code = "PLACE_CITY_REQUIRED";
    throw err;
  }
  if (!placeMatchesLaunchCity(place, config)) {
    throw launchCityUnavailableError(config);
  }
}

module.exports = {
  CITY_ALIASES,
  getLaunchCityConfig,
  normalizeCityKey,
  canonicalCityKey,
  isLaunchCityName,
  isKnownNonLaunchCity,
  suggestionMatchesLaunchCity,
  societyMatchesLaunchCity,
  placeMatchesLaunchCity,
  launchCityUnavailableError,
  assertPlaceAllowedForLaunch,
};
