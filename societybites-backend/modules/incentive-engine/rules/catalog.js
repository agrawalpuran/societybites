const OPERATORS = Object.freeze([
  "EQUALS",
  "NOT_EQUALS",
  "GREATER_THAN",
  "LESS_THAN",
  "GREATER_THAN_OR_EQUAL",
  "LESS_THAN_OR_EQUAL",
  "IN",
  "NOT_IN",
  "BETWEEN",
  "EXISTS",
]);

const COMPARISON = Object.freeze([
  "GREATER_THAN",
  "LESS_THAN",
  "GREATER_THAN_OR_EQUAL",
  "LESS_THAN_OR_EQUAL",
  "BETWEEN",
]);

const STRING_OPS = Object.freeze(["EQUALS", "NOT_EQUALS", "IN", "NOT_IN", "EXISTS"]);
const NUMBER_OPS = Object.freeze(["EQUALS", "NOT_EQUALS", "IN", "NOT_IN", "EXISTS", ...COMPARISON]);
const BOOLEAN_OPS = Object.freeze(["EQUALS", "NOT_EQUALS", "EXISTS"]);

/** Explicit attributes a campaign rule may read. Not database column paths. */
const FIELDS = Object.freeze({
  "user.role": { type: "string", values: ["buyer", "seller"] },
  "user.isNew": { type: "boolean" },
  "user.societyId": { type: "string" },
  "user.cityKey": { type: "string" },
  "order.status": { type: "string" },
  "order.paymentStatus": { type: "string" },
  "order.paymentMethod": { type: "string" },
  "order.subtotal": { type: "number" },
  "order.total": { type: "number" },
  "order.societyId": { type: "string" },
  "order.sellerId": { type: "string" },
  "order.itemCount": { type: "number" },
  "order.isFirstCompleted": { type: "boolean" },
  "listing.status": { type: "string" },
  "listing.catalogType": { type: "string" },
  "review.rating": { type: "number" },
  "referral.acquisitionKind": { type: "string", values: ["BUYER_ACQUISITION", "SELLER_ACQUISITION"] },
  "referral.qualifiedCount": { type: "number" },
  "event.type": { type: "string" },
});

const AUDIENCE_KINDS = Object.freeze([
  "ALL_USERS",
  "BUYERS",
  "SELLERS",
  "NEW_USERS",
  "EXISTING_USERS",
  "FIRST_TIME_BUYERS",
  "ACTIVE_BUYERS",
  "INACTIVE_BUYERS",
  "NEW_SELLERS",
  "SOCIETIES",
  "CITIES",
  "REGIONS",
  "CUSTOM_SEGMENT",
]);

/**
 * Triggers an administrator may store. None of these are processed in Phase 2B.
 * Event handlers arrive in a later phase.
 */
const CONFIGURABLE_TRIGGERS = Object.freeze([
  "USER_REGISTERED",
  "USER_BECAME_SELLER",
  "LISTING_PUBLISHED",
  "ORDER_QUALIFIED",
  "ORDER_CANCELLED",
  "ORDER_REJECTED",
  "REVIEW_SUBMITTED",
  "REFERRAL_ATTRIBUTED",
]);

const CAMPAIGN_CATEGORIES = Object.freeze([
  "BUYER_ACQUISITION",
  "SELLER_ACQUISITION",
  "REFERRAL",
  "REPEAT_ORDER",
  "LISTING",
  "REVIEW",
  "FESTIVE",
  "PROMOTIONAL",
]);

const REWARD_TYPES = Object.freeze([
  "FIXED_COUPON",
  "PERCENTAGE_COUPON",
  "PROMOTIONAL_CREDIT",
  "POINTS",
]);

const RECIPIENT_ROLES = Object.freeze([
  "REFERRER",
  "REFERRED",
  "BUYER",
  "SELLER",
  "TRIGGER_USER",
]);

const STACKING_MODES = Object.freeze(["STACK", "EXCLUSIVE", "FIRST_MATCH"]);

/** Explicit eligibility choice stored on the campaign version snapshot. */
const ELIGIBILITY_POLICIES = Object.freeze(["RULES", "AUDIENCE_AND_TRIGGER_ONLY"]);

const STATUSES = Object.freeze([
  "DRAFT",
  "SCHEDULED",
  "ACTIVE",
  "PAUSED",
  "COMPLETED",
  "EXPIRED",
  "TERMINATED",
]);

const MAX_RULE_DEPTH = 4;
const MAX_CONDITIONS = 30;

function operatorsFor(type) {
  if (type === "number") return NUMBER_OPS;
  if (type === "boolean") return BOOLEAN_OPS;
  return STRING_OPS;
}

module.exports = {
  OPERATORS,
  FIELDS,
  AUDIENCE_KINDS,
  CONFIGURABLE_TRIGGERS,
  CAMPAIGN_CATEGORIES,
  REWARD_TYPES,
  RECIPIENT_ROLES,
  STACKING_MODES,
  ELIGIBILITY_POLICIES,
  STATUSES,
  MAX_RULE_DEPTH,
  MAX_CONDITIONS,
  operatorsFor,
};
