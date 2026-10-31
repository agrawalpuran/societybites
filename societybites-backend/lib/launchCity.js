/**
 * Launch-city configuration for society discovery.
 * Known cities (aliases + map bias) live here. Which of them are open is
 * chosen by a super admin and applied via applyLaunchCityConfig. With one
 * city open, search keeps that city's map circle.
 */

const CITY_CATALOG = [
  {
    cityKey: "bengaluru",
    displayName: "Bengaluru",
    state: "Karnataka",
    aliases: [
      "bengaluru",
      "bangalore",
      "bengaluruurban",
      "bangaloreurban",
      "bengalururural",
      "bangalorerural",
    ],
    bias: { latitude: 12.9716, longitude: 77.5946, radiusMeters: 40000 },
  },
  {
    cityKey: "pune",
    displayName: "Pune",
    state: "Maharashtra",
    aliases: ["pune", "pimprichinchwad"],
    bias: { latitude: 18.5204, longitude: 73.8567, radiusMeters: 35000 },
  },
  {
    cityKey: "hyderabad",
    displayName: "Hyderabad",
    state: "Telangana",
    aliases: ["hyderabad", "secunderabad"],
    bias: { latitude: 17.385, longitude: 78.4867, radiusMeters: 35000 },
  },
  {
    cityKey: "mumbai",
    displayName: "Mumbai",
    state: "Maharashtra",
    aliases: ["mumbai", "bombay", "navimumbai"],
    bias: { latitude: 19.076, longitude: 72.8777, radiusMeters: 35000 },
  },
  {
    cityKey: "delhi",
    displayName: "Delhi",
    state: "Delhi",
    aliases: ["delhi", "newdelhi", "nctofdelhi"],
    bias: { latitude: 28.6139, longitude: 77.209, radiusMeters: 35000 },
  },
  {
    cityKey: "chennai",
    displayName: "Chennai",
    state: "Tamil Nadu",
    aliases: ["chennai", "madras"],
    bias: { latitude: 13.0827, longitude: 80.2707, radiusMeters: 35000 },
  },
];

const CITY_ALIASES = Object.fromEntries(
  CITY_CATALOG.map((city) => [city.cityKey, city.aliases])
);

const CITY_BIAS = Object.fromEntries(
  CITY_CATALOG.map((city) => [city.cityKey, city.bias])
);

let launchCityOverride = null;

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

function catalogEntry(cityKey) {
  return CITY_CATALOG.find((city) => city.cityKey === cityKey) || null;
}

function joinCityLabels(labels) {
  if (labels.length <= 1) return labels[0] || "";
  if (labels.length === 2) return `${labels[0]} and ${labels[1]}`;
  return `${labels.slice(0, -1).join(", ")}, and ${labels[labels.length - 1]}`;
}

function envLaunchCityConfig() {
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
    cities: [city],
    state,
    country,
    canonical,
    canonicals: canonical ? [canonical] : [],
    aliases: aliasesForCity(city),
    bias,
  };
}

function singleCatalogConfig(entry) {
  return {
    city: entry.displayName,
    cities: [entry.displayName],
    state: entry.state,
    country: "IN",
    canonical: entry.cityKey,
    canonicals: [entry.cityKey],
    aliases: entry.aliases.slice(),
    bias: { ...entry.bias },
  };
}

function configForActiveKeys(keys) {
  const normalized = [];
  for (const raw of keys || []) {
    const key = canonicalCityKey(raw);
    if (!catalogEntry(key) || normalized.includes(key)) continue;
    normalized.push(key);
  }
  if (normalized.length === 0) return null;
  const ordered = CITY_CATALOG.map((city) => city.cityKey).filter((key) =>
    normalized.includes(key)
  );
  if (ordered.length === 1) {
    const env = envLaunchCityConfig();
    if (env.canonical === ordered[0]) return env;
    return singleCatalogConfig(catalogEntry(ordered[0]));
  }
  const entries = ordered.map((key) => catalogEntry(key));
  const labels = entries.map((entry) => entry.displayName);
  return {
    city: joinCityLabels(labels),
    cities: labels,
    state: "",
    country: "IN",
    canonical: ordered[0],
    canonicals: ordered,
    aliases: entries.flatMap((entry) => entry.aliases),
    bias: null,
  };
}

function normalizeActiveCityKeys(input) {
  if (!Array.isArray(input) || input.length === 0) {
    throw httpError(400, "At least one city must stay on.", "SERVING_CITY_REQUIRED");
  }
  const keys = [];
  for (const raw of input) {
    const key = canonicalCityKey(raw);
    if (!catalogEntry(key)) {
      throw httpError(
        400,
        "Only a known city can be turned on.",
        "SERVING_CITY_UNKNOWN"
      );
    }
    if (!keys.includes(key)) keys.push(key);
  }
  return CITY_CATALOG.map((city) => city.cityKey).filter((key) => keys.includes(key));
}

function getLaunchCityConfig() {
  return launchCityOverride || envLaunchCityConfig();
}

function applyLaunchCityConfig(config) {
  launchCityOverride = config || null;
}

function clearLaunchCityConfig() {
  launchCityOverride = null;
}

function listKnownCities() {
  return CITY_CATALOG.map((city) => ({
    cityKey: city.cityKey,
    displayName: city.displayName,
    state: city.state,
  }));
}

function servingCityPayload(config = getLaunchCityConfig()) {
  const cities =
    Array.isArray(config.cities) && config.cities.length > 0
      ? config.cities
      : [config.city].filter(Boolean);
  return {
    servingCities: cities,
    servingCityLabel: joinCityLabels(cities),
  };
}

function isLaunchCityName(value, config = getLaunchCityConfig()) {
  const key = normalizeCityKey(value);
  if (!key) return false;
  return config.aliases.includes(key);
}

function activeCanonicals(config) {
  if (Array.isArray(config.canonicals) && config.canonicals.length > 0) {
    return config.canonicals;
  }
  return config.canonical ? [config.canonical] : [];
}

function isKnownNonLaunchCity(value, config = getLaunchCityConfig()) {
  const canonical = canonicalCityKey(value);
  if (!canonical) return false;
  if (activeCanonicals(config).includes(canonical)) return false;
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
  CITY_BIAS,
  getLaunchCityConfig,
  envLaunchCityConfig,
  configForActiveKeys,
  normalizeActiveCityKeys,
  applyLaunchCityConfig,
  clearLaunchCityConfig,
  listKnownCities,
  servingCityPayload,
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
