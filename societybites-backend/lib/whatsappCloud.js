const logger = require("./logger");
const { normalizeIndianPhone } = require("../utils/phone");
const { isWhatsAppOrderNotificationsEnabled } = require("./whatsappSetting");

const TEMPLATE_NAME = "hello_world";
const ORDER_TEMPLATE_NAME = "new_order_notification";
/** Example test WABA names (override via env). */
const TEST_ORDER_TEMPLATE_NAME = "test_new_order_notification";
const READY_TEMPLATE_NAME = "test_order_ready_pickup";
const COMPLETED_TEMPLATE_NAME = "test_order_completed";
const READY_TEMPLATE_ENV = "WHATSAPP_TEMPLATE_READY";
const COMPLETED_TEMPLATE_ENV = "WHATSAPP_TEMPLATE_COMPLETED";
const TEMPLATE_LANGUAGE = "en_US";
const DEFAULT_API_VERSION = "v21.0";
const DEFAULT_TIMEOUT_MS = 8000;
const MAX_ITEM_SUMMARY_LENGTH = 200;
const MAX_ITEM_LINES = 12;

function envFlagOff(raw) {
  const value = String(raw ?? "").trim().toLowerCase();
  return value === "false" || value === "0" || value === "off" || value === "no";
}

function graphVersion(raw) {
  const value = String(raw || DEFAULT_API_VERSION).trim() || DEFAULT_API_VERSION;
  return value.startsWith("v") ? value : `v${value}`;
}

function timeoutMs(raw) {
  const parsed = Number(raw);
  if (Number.isFinite(parsed) && parsed > 0) return parsed;
  return DEFAULT_TIMEOUT_MS;
}

function isOrderTemplateName(raw) {
  const value = String(raw ?? "").trim();
  if (!value || value === TEMPLATE_NAME) return false;
  return /^[a-z0-9_]+$/.test(value);
}

function resolveTemplateName(raw) {
  const value = String(raw ?? "").trim();
  if (isOrderTemplateName(value)) return value;
  return TEMPLATE_NAME;
}

function resolveTemplateLanguage(raw) {
  const value = String(raw ?? "").trim();
  if (value === "en" || value === "en_US") return value;
  return TEMPLATE_LANGUAGE;
}

function readConfig(env, overrides = {}) {
  const source = env || process.env;
  const templateRaw =
    overrides.templateName !== undefined
      ? overrides.templateName
      : source.WHATSAPP_TEMPLATE_NAME;
  return {
    emergencyOff: envFlagOff(source.WHATSAPP_ENABLED),
    token: String(source.WHATSAPP_TOKEN || "").trim(),
    phoneNumberId: String(source.WHATSAPP_PHONE_NUMBER_ID || "").trim(),
    apiVersion: graphVersion(source.WHATSAPP_API_VERSION),
    timeoutMs: timeoutMs(source.WHATSAPP_TIMEOUT_MS),
    templateName: resolveTemplateName(templateRaw),
    templateLanguage: resolveTemplateLanguage(source.WHATSAPP_TEMPLATE_LANGUAGE),
  };
}

function templateNameFromEnv(env, envKey) {
  const source = env || process.env;
  const value = String(source[envKey] || "").trim();
  return isOrderTemplateName(value) ? value : null;
}

function isConfigured(config) {
  return Boolean(config.token && config.phoneNumberId);
}

function sellerPhoneFromOrder(order) {
  return (
    order &&
    order.items &&
    order.items[0] &&
    order.items[0].listing &&
    order.items[0].listing.seller &&
    order.items[0].listing.seller.phone
  );
}

function buyerPhoneFromOrder(order) {
  return order && order.buyer && order.buyer.phone;
}

function toWhatsAppRecipient(raw) {
  const canonical = normalizeIndianPhone(raw);
  if (!canonical) return null;
  return canonical.slice(1);
}

function graphMessagesUrl(config) {
  return `https://graph.facebook.com/${config.apiVersion}/${config.phoneNumberId}/messages`;
}

function textParameter(value, fallback) {
  const cleaned = String(value ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/ {2,}/g, " ")
    .trim();
  return cleaned || fallback;
}

function numericAmount(value) {
  if (value === null || value === undefined || value === "") return NaN;
  if (typeof value === "object" && typeof value.toNumber === "function") {
    return value.toNumber();
  }
  return Number(value);
}

function formatOrderAmount(value) {
  const amount = numericAmount(value);
  if (!Number.isFinite(amount) || amount < 0) return null;
  const rounded = Math.round(amount * 100) / 100;
  if (rounded === Math.floor(rounded)) return String(rounded);
  return rounded.toFixed(2);
}

function sellerNameFromOrder(order) {
  const seller =
    order &&
    order.items &&
    order.items[0] &&
    order.items[0].listing &&
    order.items[0].listing.seller;
  return textParameter(seller && seller.name, "Seller");
}

function customerNameFromOrder(order) {
  return textParameter(order && order.buyer && order.buyer.name, "Customer");
}

function formatItemsSummary(items) {
  const list = Array.isArray(items) ? items : [];
  const parts = [];
  let omitted = false;
  for (const item of list) {
    const rawQty = Number(item && item.quantity);
    if (!Number.isFinite(rawQty) || rawQty <= 0) continue;
    if (parts.length >= MAX_ITEM_LINES) {
      omitted = true;
      break;
    }
    const name = textParameter(item && item.listing && item.listing.name, "Item");
    parts.push(`${Math.round(rawQty)} x ${name}`);
  }
  if (parts.length === 0) return "Items";
  let summary = parts.join(", ");
  if (omitted) summary = `${summary}, ...`;
  if (summary.length <= MAX_ITEM_SUMMARY_LENGTH) return summary;
  return `${summary.slice(0, MAX_ITEM_SUMMARY_LENGTH - 3).trimEnd()}...`;
}

/** Body params for seller new-order templates: seller, order number, customer, items, amount. */
function orderTemplateParameters(order) {
  const amount = formatOrderAmount(order && order.total);
  if (amount == null) return null;
  return [
    sellerNameFromOrder(order),
    textParameter(order && order.orderNumber, "Order"),
    customerNameFromOrder(order),
    formatItemsSummary(order && order.items),
    amount,
  ];
}

/** Body params for buyer status templates: customer, order number, seller, items, amount. */
function buyerOrderTemplateParameters(order) {
  const amount = formatOrderAmount(order && order.total);
  if (amount == null) return null;
  return [
    customerNameFromOrder(order),
    textParameter(order && order.orderNumber, "Order"),
    sellerNameFromOrder(order),
    formatItemsSummary(order && order.items),
    amount,
  ];
}

function templatePayload(to, options) {
  const templateName = options && options.templateName;
  if (isOrderTemplateName(templateName)) {
    const parameters = Array.isArray(options.parameters) ? options.parameters : [];
    return {
      messaging_product: "whatsapp",
      to,
      type: "template",
      template: {
        name: templateName,
        language: {
          code: resolveTemplateLanguage(options.language),
        },
        components: [
          {
            type: "body",
            parameters: parameters.map((text) => ({ type: "text", text: String(text) })),
          },
        ],
      },
    };
  }

  return {
    messaging_product: "whatsapp",
    to,
    type: "template",
    template: {
      name: TEMPLATE_NAME,
      language: { code: TEMPLATE_LANGUAGE },
    },
  };
}

function messageIdFromBody(body) {
  const id =
    body &&
    body.messages &&
    body.messages[0] &&
    body.messages[0].id;
  return id ? String(id) : null;
}

async function fetchWithTimeout(fetchFn, url, options, ms) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetchFn(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function isTransientWhatsAppError(err, statusCode) {
  if (err && err.name === "AbortError") return true;
  if (statusCode === 429) return true;
  if (statusCode >= 500 && statusCode <= 599) return true;
  return false;
}

async function postTemplateOnce(config, to, deps, parameters) {
  const fetchFn = deps.fetch || globalThis.fetch;
  if (typeof fetchFn !== "function") {
    throw new Error("fetch is not available");
  }
  const response = await fetchWithTimeout(
    fetchFn,
    graphMessagesUrl(config),
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(
        templatePayload(to, {
          templateName: config.templateName,
          language: config.templateLanguage,
          parameters,
        })
      ),
    },
    config.timeoutMs
  );

  let body = null;
  try {
    body = await response.json();
  } catch (_) {
    body = null;
  }

  if (!response.ok) {
    const apiMessage =
      (body && body.error && body.error.message) || `HTTP ${response.status}`;
    const err = new Error(apiMessage);
    err.statusCode = response.status;
    throw err;
  }

  return messageIdFromBody(body);
}

async function postTemplate(config, to, deps, parameters) {
  const maxAttempts = 2;
  let lastErr;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await postTemplateOnce(config, to, deps, parameters);
    } catch (err) {
      lastErr = err;
      const retryable = isTransientWhatsAppError(err, err.statusCode);
      if (!retryable || attempt >= maxAttempts) throw err;
      logger.warn("whatsapp", `Graph send retry ${attempt}/${maxAttempts - 1}`, {
        error: err.message,
      });
      await new Promise((resolve) => setTimeout(resolve, 600));
    }
  }
  throw lastErr;
}

function sendWhatsAppSafely(inner, order, kind) {
  return Promise.resolve()
    .then(() => inner(order))
    .catch((err) => {
      logger.error(
        "whatsapp",
        `${kind}: ${err && err.message ? err.message : String(err)}`
      );
      return { sent: false, reason: "error" };
    });
}

async function sendWhatsAppTemplatedMessage(order, options, deps) {
  const isEnabled = deps.isEnabled || isWhatsAppOrderNotificationsEnabled;
  if (!(await isEnabled())) {
    logWhatsAppSkipped(options.logKind || "status", order, "admin_off");
    return { sent: false, reason: "admin_off" };
  }

  const templateName = templateNameFromEnv(deps.env, options.templateEnvKey);
  if (!templateName) {
    logWhatsAppSkipped(options.logKind || "status", order, "no_template");
    return { sent: false, reason: "no_template" };
  }

  const config = readConfig(deps.env, { templateName });
  if (config.emergencyOff) {
    logWhatsAppSkipped(options.logKind || "status", order, "emergency_off");
    return { sent: false, reason: "emergency_off" };
  }
  if (!isConfigured(config)) {
    logWhatsAppSkipped(options.logKind || "status", order, "unconfigured");
    return { sent: false, reason: "unconfigured" };
  }

  const recipient = toWhatsAppRecipient(options.recipientPhone(order));
  if (!recipient) {
    logWhatsAppSkipped(options.logKind || "status", order, "no_phone");
    return { sent: false, reason: "no_phone" };
  }

  const parameters = options.buildParameters(order);
  if (!parameters) {
    logWhatsAppSkipped(options.logKind || "status", order, "invalid_amount");
    return { sent: false, reason: "invalid_amount" };
  }

  const messageId = await postTemplate(config, recipient, deps, parameters);
  logger.info("whatsapp", `${options.logKind} ${order && order.orderNumber}`, {
    orderNumber: order && order.orderNumber,
    messageId,
  });
  return { sent: true, messageId, to: recipient };
}

/**
 * Independent of FCM. Never rejects. Makes no Graph call when disabled,
 * unconfigured, or the seller phone is missing/invalid.
 */
function sendWhatsAppOrderNotification(order, deps = {}) {
  return sendWhatsAppSafely(
    (payload) => sendWhatsAppOrderNotificationInner(payload, deps),
    order,
    "new_order"
  );
}

function logWhatsAppSkipped(kind, order, reason, extra) {
  logger.warn("whatsapp", `${kind} skipped ${order && order.orderNumber}: ${reason}`, {
    orderNumber: order && order.orderNumber,
    reason,
    ...(extra && typeof extra === "object" ? extra : {}),
  });
}

async function sendWhatsAppOrderNotificationInner(order, deps) {
  const isEnabled = deps.isEnabled || isWhatsAppOrderNotificationsEnabled;
  if (!(await isEnabled())) {
    logWhatsAppSkipped("new_order", order, "admin_off");
    return { sent: false, reason: "admin_off" };
  }

  const config = readConfig(deps.env);
  if (config.emergencyOff) {
    logWhatsAppSkipped("new_order", order, "emergency_off");
    return { sent: false, reason: "emergency_off" };
  }
  if (!isConfigured(config)) {
    logWhatsAppSkipped("new_order", order, "unconfigured");
    return { sent: false, reason: "unconfigured" };
  }

  const recipient = toWhatsAppRecipient(sellerPhoneFromOrder(order));
  if (!recipient) {
    logWhatsAppSkipped("new_order", order, "no_phone");
    return { sent: false, reason: "no_phone" };
  }

  let parameters;
  if (isOrderTemplateName(config.templateName)) {
    parameters = orderTemplateParameters(order);
    if (!parameters) {
      logWhatsAppSkipped("new_order", order, "invalid_amount");
      return { sent: false, reason: "invalid_amount" };
    }
  }

  const messageId = await postTemplate(config, recipient, deps, parameters);
  logger.info("whatsapp", `sent ${order && order.orderNumber}`, {
    orderNumber: order && order.orderNumber,
    messageId,
    template: config.templateName,
  });
  return { sent: true, messageId, to: recipient };
}

function sendWhatsAppReadyNotification(order, deps = {}) {
  return sendWhatsAppSafely(
    (payload) =>
      sendWhatsAppTemplatedMessage(
        payload,
        {
          templateEnvKey: READY_TEMPLATE_ENV,
          recipientPhone: buyerPhoneFromOrder,
          buildParameters: buyerOrderTemplateParameters,
          logKind: "ready",
        },
        deps
      ),
    order,
    "ready"
  );
}

function sendWhatsAppCompletedNotification(order, deps = {}) {
  return sendWhatsAppSafely(
    (payload) =>
      sendWhatsAppTemplatedMessage(
        payload,
        {
          templateEnvKey: COMPLETED_TEMPLATE_ENV,
          recipientPhone: buyerPhoneFromOrder,
          buildParameters: buyerOrderTemplateParameters,
          logKind: "completed",
        },
        deps
      ),
    order,
    "completed"
  );
}

function dispatchWhatsAppStatusNotification(order, status) {
  if (status === "ready") {
    void sendWhatsAppReadyNotification(order);
  } else if (status === "completed") {
    void sendWhatsAppCompletedNotification(order);
  }
}

module.exports = {
  TEMPLATE_NAME,
  ORDER_TEMPLATE_NAME,
  TEST_ORDER_TEMPLATE_NAME,
  READY_TEMPLATE_NAME,
  COMPLETED_TEMPLATE_NAME,
  READY_TEMPLATE_ENV,
  COMPLETED_TEMPLATE_ENV,
  TEMPLATE_LANGUAGE,
  sendWhatsAppOrderNotification,
  sendWhatsAppReadyNotification,
  sendWhatsAppCompletedNotification,
  dispatchWhatsAppStatusNotification,
  readConfig,
  isConfigured,
  toWhatsAppRecipient,
  sellerPhoneFromOrder,
  buyerPhoneFromOrder,
  graphMessagesUrl,
  templatePayload,
  orderTemplateParameters,
  buyerOrderTemplateParameters,
};
