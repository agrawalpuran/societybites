const { httpError } = require("../lib/httpError");
const { CONFIGURABLE_TRIGGERS } = require("../rules/catalog");

const ENTITY_BY_TYPE = Object.freeze({
  USER_REGISTERED: "user",
  USER_BECAME_SELLER: "user",
  LISTING_PUBLISHED: "listing",
  ORDER_QUALIFIED: "order",
  ORDER_CANCELLED: "order",
  ORDER_REJECTED: "order",
  REVIEW_SUBMITTED: "review",
  REFERRAL_ATTRIBUTED: "referral",
});

const ORDER_TERMINAL_TYPES = Object.freeze(["ORDER_QUALIFIED", "ORDER_CANCELLED", "ORDER_REJECTED"]);
const FORBIDDEN_PAYLOAD_KEYS = new Set(["expression", "sql", "script", "query", "eval", "function", "code"]);
const MAX_PAYLOAD_KEYS = 30;
const MAX_PAYLOAD_CHARS = 4000;

function text(value, label, max) {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed) throw httpError(400, `${label} is required`, "EVENT_INVALID");
  if (trimmed.length > max) throw httpError(400, `${label} must be at most ${max} characters`, "EVENT_INVALID");
  return trimmed;
}

function validatePayload(payload) {
  if (payload == null) return {};
  if (typeof payload !== "object" || Array.isArray(payload)) {
    throw httpError(400, "Event payload must be an object", "EVENT_INVALID");
  }
  const keys = Object.keys(payload);
  if (keys.length > MAX_PAYLOAD_KEYS) {
    throw httpError(400, "Event payload has too many fields", "EVENT_INVALID");
  }
  const clean = {};
  for (const key of keys) {
    if (!/^[a-zA-Z][a-zA-Z0-9_.]{0,39}$/.test(key) || FORBIDDEN_PAYLOAD_KEYS.has(key)) {
      throw httpError(400, `Event payload field is not allowed: ${key}`, "EVENT_INVALID");
    }
    const value = payload[key];
    if (value == null) {
      clean[key] = null;
    } else if (typeof value === "boolean") {
      clean[key] = value;
    } else if (typeof value === "number" && Number.isFinite(value)) {
      clean[key] = value;
    } else if (typeof value === "string" && value.length <= 200) {
      clean[key] = value;
    } else {
      throw httpError(400, `Event payload field ${key} must be text, a number, or a boolean`, "EVENT_INVALID");
    }
  }
  if (JSON.stringify(clean).length > MAX_PAYLOAD_CHARS) {
    throw httpError(400, "Event payload is too large", "EVENT_INVALID");
  }
  return clean;
}

function eventIdentity(type, entityId, acquisitionKind) {
  if (type === "REFERRAL_ATTRIBUTED") return `${type}:${entityId}:${acquisitionKind}`;
  return `${type}:${entityId}`;
}

function validateIngest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw httpError(400, "Event body is invalid", "EVENT_INVALID");
  }
  const type = body.type;
  if (!CONFIGURABLE_TRIGGERS.includes(type)) {
    throw httpError(400, "Unsupported event type", "EVENT_TYPE_INVALID");
  }
  if (body.schemaVersion != null && body.schemaVersion !== 1) {
    throw httpError(400, "Unsupported event schema version", "EVENT_INVALID");
  }
  const entityId = text(body.entityId, "Entity id", 80);
  if (!body.occurredAt) throw httpError(400, "occurredAt is required", "EVENT_INVALID");
  const occurredAt = new Date(body.occurredAt);
  if (Number.isNaN(occurredAt.getTime())) throw httpError(400, "occurredAt is not a valid date", "EVENT_INVALID");
  let acquisitionKind = null;
  if (type === "REFERRAL_ATTRIBUTED") {
    acquisitionKind = text(body.acquisitionKind, "Acquisition kind", 40);
    if (acquisitionKind !== "BUYER_ACQUISITION" && acquisitionKind !== "SELLER_ACQUISITION") {
      throw httpError(400, "Acquisition kind must be BUYER_ACQUISITION or SELLER_ACQUISITION", "EVENT_INVALID");
    }
  }
  const userId = body.userId == null || body.userId === "" ? null : text(body.userId, "User id", 80);
  return {
    type,
    entityType: ENTITY_BY_TYPE[type],
    entityId,
    eventId: eventIdentity(type, entityId, acquisitionKind),
    schemaVersion: 1,
    occurredAt,
    userId,
    payload: validatePayload(body.payload),
    acquisitionKind,
  };
}

module.exports = {
  ENTITY_BY_TYPE,
  ORDER_TERMINAL_TYPES,
  eventIdentity,
  validateIngest,
  validatePayload,
};
