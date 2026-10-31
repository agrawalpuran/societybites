const prisma = require("./prisma");
const {
  applyLaunchCityConfig,
  clearLaunchCityConfig,
  configForActiveKeys,
  getLaunchCityConfig,
  listKnownCities,
  normalizeActiveCityKeys,
} = require("./launchCity");

const SERVING_CITIES_KEY = "serving_cities";
const CACHE_MS = 15_000;

let cachedAt = 0;

function listServingCityRows(config = getLaunchCityConfig()) {
  const active = new Set(
    Array.isArray(config.canonicals) && config.canonicals.length
      ? config.canonicals
      : config.canonical
        ? [config.canonical]
        : []
  );
  return listKnownCities().map((city) => ({
    ...city,
    active: active.has(city.cityKey),
  }));
}

async function refreshServingCities({ bypassCache = false } = {}) {
  const now = Date.now();
  if (!bypassCache && cachedAt && now - cachedAt < CACHE_MS) {
    return getLaunchCityConfig();
  }

  try {
    const row = await prisma.appSetting.findUnique({
      where: { key: SERVING_CITIES_KEY },
    });
    let parsed = null;
    if (row && row.value) {
      try {
        parsed = JSON.parse(row.value);
      } catch (_err) {
        parsed = null;
      }
    }
    const config = Array.isArray(parsed) ? configForActiveKeys(parsed) : null;
    if (config) applyLaunchCityConfig(config);
    else clearLaunchCityConfig();
    cachedAt = now;
  } catch (_err) {
    if (!cachedAt) cachedAt = now;
  }

  return getLaunchCityConfig();
}

async function saveActiveCityKeys(keys) {
  const normalized = normalizeActiveCityKeys(keys);
  const value = JSON.stringify(normalized);
  await prisma.appSetting.upsert({
    where: { key: SERVING_CITIES_KEY },
    update: { value },
    create: { key: SERVING_CITIES_KEY, value },
  });
  const config = configForActiveKeys(normalized);
  applyLaunchCityConfig(config);
  cachedAt = Date.now();
  return config;
}

module.exports = {
  SERVING_CITIES_KEY,
  listServingCityRows,
  refreshServingCities,
  saveActiveCityKeys,
};
