const logger = require("./logger");
const { normalizeIndianPhone } = require("../utils/phone");
const { isWhatsAppOrderNotificationsEnabled } = require("./whatsappSetting");

const TEMPLATE_NAME = "hello_world";
const ORDER_TEMPLATE_NAME = "new_order_notification";
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

function resolveTemplateName(raw) {
  const value = String(raw ?? "").trim();
  if (value === ORDER_TEMPLATE_NAME) return ORDER_TEMPLATE_NAME;
  return TEMPLATE_NAME;
}

function readConfig(env) {
  const source = env || process.env;
  return {
    emergencyOff: envFlagOff(source.WHATSAPP_ENABLED),
    token: String(source.WHATSAPP_TOKEN || "").trim(),
    phoneNumberId: String(source.WHATSAPP_PHONE_NUMBER_ID || "").trim(),
    apiVersion: graphVersion(source.WHATSAPP_API_VERSION),
    timeoutMs: timeoutMs(source.WHATSAPP_TIMEOUT_MS),
    templateName: resolveTemplateName(source.WHATSAPP_TEMPLATE_NAME),
  };
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

function templatePayload(to, options) {
  if (options && options.templateName === ORDER_TEMPLATE_NAME) {
    const parameters = Array.isArray(options.parameters) ? options.parameters : [];
    return {
      messaging_product: "whatsapp",
      to,
      type: "template",
      template: {
        name: ORDER_TEMPLATE_NAME,
        language: { code: TEMPLATE_LANGUAGE },
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

async function postTemplate(config, to, deps, parameters) {
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

/**
 * Independent of FCM. Never rejects. Makes no Graph call when disabled,
 * unconfigured, or the seller phone is missing/invalid.
 */
function sendWhatsAppOrderNotification(order, deps = {}) {
  return Promise.resolve()
    .then(() => sendWhatsAppOrderNotificationInner(order, deps))
    .catch((err) => {
      logger.error("whatsapp", err && err.message ? err.message : String(err));
      return { sent: false, reason: "error" };
    });
}

async function sendWhatsAppOrderNotificationInner(order, deps) {
  const isEnabled =
    deps.isEnabled || isWhatsAppOrderNotificationsEnabled;
  if (!(await isEnabled())) {
    return { sent: false, reason: "admin_off" };
  }

  const config = readConfig(deps.env);
  if (config.emergencyOff) {
    return { sent: false, reason: "emergency_off" };
  }
  if (!isConfigured(config)) {
    return { sent: false, reason: "unconfigured" };
  }

  const recipient = toWhatsAppRecipient(sellerPhoneFromOrder(order));
  if (!recipient) {
    return { sent: false, reason: "no_phone" };
  }

  let parameters;
  if (config.templateName === ORDER_TEMPLATE_NAME) {
    parameters = orderTemplateParameters(order);
    if (!parameters) {
      return { sent: false, reason: "invalid_amount" };
    }
  }

  const messageId = await postTemplate(config, recipient, deps, parameters);
  logger.info("whatsapp", `sent ${order && order.orderNumber}`, {
    orderNumber: order && order.orderNumber,
    messageId,
  });
  return { sent: true, messageId, to: recipient };
}

module.exports = {
  TEMPLATE_NAME,
  ORDER_TEMPLATE_NAME,
  TEMPLATE_LANGUAGE,
  sendWhatsAppOrderNotification,
  readConfig,
  isConfigured,
  toWhatsAppRecipient,
  sellerPhoneFromOrder,
  graphMessagesUrl,
  templatePayload,
  orderTemplateParameters,
};
