const prisma = require("./prisma");

const MIN_IOS_BUILD_KEY = "min_ios_build";
const MIN_ANDROID_BUILD_KEY = "min_android_build";
const IOS_UPDATE_URL_KEY = "ios_update_url";
const ANDROID_UPDATE_URL_KEY = "android_update_url";

const DEFAULT_MIN_BUILD = 0;
const CACHE_MS = 60_000;

let cached = null;
let cachedAt = 0;

function parseBuild(value, fallback = DEFAULT_MIN_BUILD) {
  if (value == null || value === "") return fallback;
  const n = Number.parseInt(String(value).trim(), 10);
  if (!Number.isFinite(n) || n < 0) return fallback;
  return n;
}

function parseUrl(value) {
  const text = String(value || "").trim();
  return text || "";
}

async function readSetting(key) {
  const row = await prisma.appSetting.findUnique({ where: { key } });
  return row?.value ?? null;
}

async function writeSetting(key, value) {
  return prisma.appSetting.upsert({
    where: { key },
    update: { value: String(value) },
    create: { key, value: String(value) },
  });
}

function emptyConfig() {
  return {
    minIosBuild: DEFAULT_MIN_BUILD,
    minAndroidBuild: DEFAULT_MIN_BUILD,
    iosUpdateUrl: "",
    androidUpdateUrl: "",
  };
}

async function getForceUpdateConfig({ bypassCache = false } = {}) {
  const now = Date.now();
  if (!bypassCache && cached !== null && now - cachedAt < CACHE_MS) {
    return cached;
  }

  const [minIos, minAndroid, iosUrl, androidUrl] = await Promise.all([
    readSetting(MIN_IOS_BUILD_KEY),
    readSetting(MIN_ANDROID_BUILD_KEY),
    readSetting(IOS_UPDATE_URL_KEY),
    readSetting(ANDROID_UPDATE_URL_KEY),
  ]);

  cached = {
    minIosBuild: parseBuild(minIos),
    minAndroidBuild: parseBuild(minAndroid),
    iosUpdateUrl: parseUrl(iosUrl),
    androidUpdateUrl: parseUrl(androidUrl),
  };
  cachedAt = now;
  return cached;
}

async function setForceUpdateConfig(input = {}) {
  const updates = {};

  if (input.minIosBuild !== undefined && input.minIosBuild !== null) {
    const value = parseBuild(input.minIosBuild, Number.NaN);
    if (!Number.isFinite(value) || value < 0) {
      const err = new Error("minIosBuild must be an integer >= 0");
      err.statusCode = 400;
      throw err;
    }
    await writeSetting(MIN_IOS_BUILD_KEY, value);
    updates.minIosBuild = value;
  }

  if (input.minAndroidBuild !== undefined && input.minAndroidBuild !== null) {
    const value = parseBuild(input.minAndroidBuild, Number.NaN);
    if (!Number.isFinite(value) || value < 0) {
      const err = new Error("minAndroidBuild must be an integer >= 0");
      err.statusCode = 400;
      throw err;
    }
    await writeSetting(MIN_ANDROID_BUILD_KEY, value);
    updates.minAndroidBuild = value;
  }

  if (input.iosUpdateUrl !== undefined && input.iosUpdateUrl !== null) {
    const value = parseUrl(input.iosUpdateUrl);
    await writeSetting(IOS_UPDATE_URL_KEY, value);
    updates.iosUpdateUrl = value;
  }

  if (input.androidUpdateUrl !== undefined && input.androidUpdateUrl !== null) {
    const value = parseUrl(input.androidUpdateUrl);
    await writeSetting(ANDROID_UPDATE_URL_KEY, value);
    updates.androidUpdateUrl = value;
  }

  if (!Object.keys(updates).length) {
    return null;
  }

  cached = null;
  cachedAt = 0;
  const current = await getForceUpdateConfig({ bypassCache: true });
  return current;
}

module.exports = {
  MIN_IOS_BUILD_KEY,
  MIN_ANDROID_BUILD_KEY,
  IOS_UPDATE_URL_KEY,
  ANDROID_UPDATE_URL_KEY,
  DEFAULT_MIN_BUILD,
  emptyConfig,
  getForceUpdateConfig,
  setForceUpdateConfig,
};
