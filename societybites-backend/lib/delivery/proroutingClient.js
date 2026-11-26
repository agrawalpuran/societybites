const logger = require("../logger");

class ProroutingHttpError extends Error {
  constructor(message, status, body) {
    super(message);
    this.statusCode = status >= 500 ? 502 : status || 502;
    this.body = body;
  }
}

let fetchImpl = defaultFetch;

function setDeliveryFetch(fn) {
  fetchImpl = fn;
}

function resetDeliveryFetch() {
  fetchImpl = defaultFetch;
}

async function defaultFetch(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_err) {
    json = null;
  }
  if (!response.ok || (json && json.status === 0)) {
    const message =
      (json && (json.message || json.error)) || text || response.statusText;
    throw new ProroutingHttpError(message, response.status || 400, json);
  }
  return json;
}

function proroutingConfig(env = process.env) {
  return {
    apiKey: String((env && env.PROROUTING_API_KEY) || "").trim(),
    baseUrl: String((env && env.PROROUTING_BASE_URL) || "")
      .trim()
      .replace(/\/+$/, ""),
    webhookToken: String((env && env.PROROUTING_WEBHOOK_TOKEN) || "").trim(),
  };
}

function isProroutingConfigured(config = proroutingConfig()) {
  return Boolean(config.apiKey && config.baseUrl);
}

async function proroutingRequest({ method, path, body, config }) {
  const cfg = config || proroutingConfig();
  if (!isProroutingConfigured(cfg)) {
    const err = new Error("Prorouting is not configured");
    err.statusCode = 503;
    throw err;
  }
  return fetchImpl(`${cfg.baseUrl}${path}`, {
    method,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "x-pro-api-key": cfg.apiKey,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

async function estimate(payload, config) {
  return proroutingRequest({
    method: "POST",
    path: "/partner/estimate",
    body: payload,
    config,
  });
}

async function createOrder(payload, config) {
  return proroutingRequest({
    method: "POST",
    path: "/partner/order/createasync",
    body: payload,
    config,
  });
}

async function updateOrder(payload, config) {
  return proroutingRequest({
    method: "POST",
    path: "/partner/order/update",
    body: payload,
    config,
  });
}

async function cancelOrder(payload, config) {
  return proroutingRequest({
    method: "POST",
    path: "/partner/order/cancel",
    body: payload,
    config,
  });
}

async function getStatus(payload, config) {
  return proroutingRequest({
    method: "POST",
    path: "/partner/order/status",
    body: payload,
    config,
  });
}

async function trackOrder(payload, config) {
  return proroutingRequest({
    method: "POST",
    path: "/partner/order/track",
    body: payload,
    config,
  });
}

function logProroutingError(scope, error) {
  logger.error("delivery", `${scope}: ${error && error.message}`, {
    statusCode: error && error.statusCode,
  });
}

module.exports = {
  ProroutingHttpError,
  setDeliveryFetch,
  resetDeliveryFetch,
  proroutingConfig,
  isProroutingConfigured,
  estimate,
  createOrder,
  updateOrder,
  cancelOrder,
  getStatus,
  trackOrder,
  logProroutingError,
};
