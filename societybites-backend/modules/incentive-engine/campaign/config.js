const { httpError } = require("../lib/httpError");
const {
  AUDIENCE_KINDS,
  CAMPAIGN_CATEGORIES,
  CONFIGURABLE_TRIGGERS,
  ELIGIBILITY_POLICIES,
  RECIPIENT_ROLES,
  REWARD_TYPES,
  STACKING_MODES,
} = require("../rules/catalog");
const { validateRules } = require("../rules/validate");

function text(value, label, max) {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed) throw httpError(400, `${label} is required`);
  if (trimmed.length > max) throw httpError(400, `${label} must be at most ${max} characters`);
  return trimmed;
}

function optionalText(value, label, max) {
  if (value == null || value === "") return null;
  return text(value, label, max);
}

function money(value, label, { allowZero = false } = {}) {
  const amount = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  if (typeof amount !== "number" || !Number.isFinite(amount)) {
    throw httpError(400, `${label} must be a number`);
  }
  if (amount < 0 || (!allowZero && amount === 0)) {
    throw httpError(400, allowZero ? `${label} cannot be negative` : `${label} must be greater than zero`);
  }
  return amount.toFixed(2);
}

function parseDate(value, label) {
  if (value == null || value === "") return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw httpError(400, `${label} is not a valid date`);
  return date.toISOString();
}

function assertWindow(startsAt, endsAt) {
  if (startsAt && endsAt && new Date(startsAt) >= new Date(endsAt)) {
    throw httpError(400, "Campaign end must be after the start");
  }
}

function parseHeader(body, { partial = false } = {}) {
  const source = body && typeof body === "object" ? body : {};
  const data = {};
  if (!partial || source.name != null) data.name = text(source.name, "Campaign name", 80);
  if (!partial || source.category != null) {
    const category = text(source.category, "Campaign category", 40);
    if (!CAMPAIGN_CATEGORIES.includes(category)) {
      throw httpError(400, `Campaign category must be one of: ${CAMPAIGN_CATEGORIES.join(", ")}`);
    }
    data.category = category;
  }
  if (source.description !== undefined) data.description = optionalText(source.description, "Description", 500);
  if (source.priority !== undefined) {
    const priority = Number(source.priority);
    if (!Number.isInteger(priority) || priority < 0 || priority > 1000) {
      throw httpError(400, "Priority must be a whole number from 0 to 1000");
    }
    data.priority = priority;
  }
  if (source.stackingMode !== undefined) {
    if (!STACKING_MODES.includes(source.stackingMode)) {
      throw httpError(400, `Stacking mode must be one of: ${STACKING_MODES.join(", ")}`);
    }
    data.stackingMode = source.stackingMode;
  }
  if (source.startsAt !== undefined) data.startsAt = parseDate(source.startsAt, "Start date");
  if (source.endsAt !== undefined) data.endsAt = parseDate(source.endsAt, "End date");
  if (source.status != null && source.status !== "DRAFT") {
    throw httpError(400, "Campaign status cannot be set from the editor. Use the lifecycle action.");
  }
  return data;
}

function idList(value, label) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 50) {
    throw httpError(400, `${label} requires 1 to 50 entries`);
  }
  return value.map((item) => text(item, label, 80));
}

function parseAudience(row) {
  if (!row || typeof row !== "object") throw httpError(400, "Audience entry is invalid");
  if (!AUDIENCE_KINDS.includes(row.kind)) {
    throw httpError(400, `Unsupported audience: ${row.kind}`);
  }
  const payload = row.payload && typeof row.payload === "object" ? row.payload : {};
  if (row.kind === "SOCIETIES") return { kind: row.kind, payload: { societyIds: idList(payload.societyIds, "Society") } };
  if (row.kind === "CITIES") return { kind: row.kind, payload: { cityKeys: idList(payload.cityKeys, "City") } };
  if (row.kind === "REGIONS") return { kind: row.kind, payload: { regions: idList(payload.regions, "Region") } };
  if (row.kind === "CUSTOM_SEGMENT") {
    return { kind: row.kind, payload: { segmentKey: text(payload.segmentKey, "Segment", 80) } };
  }
  return { kind: row.kind, payload: {} };
}

function parseAudiences(rows) {
  if (!Array.isArray(rows)) throw httpError(400, "Audiences must be a list");
  if (rows.length > 20) throw httpError(400, "A campaign cannot have more than 20 audiences");
  const parsed = rows.map(parseAudience);
  if (parsed.some((row) => row.kind === "ALL_USERS") && parsed.length > 1) {
    throw httpError(400, "ALL_USERS cannot be combined with another audience", "AUDIENCE_COMBINATION");
  }
  return parsed;
}

function rulesTreeReady(rules) {
  if (!rules || typeof rules !== "object" || Array.isArray(rules)) return false;
  if (Array.isArray(rules.conditions)) return rules.conditions.length > 0;
  return Boolean(rules.field && rules.operator);
}

function parseEligibility(body) {
  const source = body && typeof body === "object" ? body : {};
  if (!ELIGIBILITY_POLICIES.includes(source.eligibility)) {
    throw httpError(400, "Eligibility policy must be RULES or AUDIENCE_AND_TRIGGER_ONLY", "ELIGIBILITY_REQUIRED");
  }
  if (source.eligibility === "AUDIENCE_AND_TRIGGER_ONLY") {
    if (source.rules != null) {
      throw httpError(400, "Audience and trigger policy does not take a rule tree", "RULES_NOT_ALLOWED");
    }
    return { eligibility: source.eligibility, rules: null };
  }
  const rules = validateRules(source.rules);
  if (!rulesTreeReady(rules)) {
    throw httpError(400, "Rules policy requires a non-empty rule tree", "RULES_REQUIRED");
  }
  return { eligibility: "RULES", rules };
}

function parseTriggers(rows) {
  if (!Array.isArray(rows)) throw httpError(400, "Triggers must be a list");
  if (rows.length > CONFIGURABLE_TRIGGERS.length) throw httpError(400, "Too many triggers");
  const seen = new Set();
  return rows.map((row) => {
    const eventType = typeof row === "string" ? row : row && row.eventType;
    if (!CONFIGURABLE_TRIGGERS.includes(eventType)) {
      throw httpError(400, `Unsupported trigger: ${eventType}. Configured triggers are not processed until a later phase.`);
    }
    if (seen.has(eventType)) throw httpError(400, `Duplicate trigger: ${eventType}`);
    seen.add(eventType);
    return { eventType, processor: "NOT_IMPLEMENTED" };
  });
}

function parseRewards(rows) {
  if (!Array.isArray(rows)) throw httpError(400, "Rewards must be a list");
  if (rows.length > 10) throw httpError(400, "A campaign cannot define more than 10 rewards");
  const seen = new Set();
  return rows.map((row) => {
    if (!row || typeof row !== "object") throw httpError(400, "Reward definition is invalid");
    const slot = text(row.slot, "Reward slot", 40);
    if (seen.has(slot)) throw httpError(400, `Duplicate reward slot: ${slot}`);
    seen.add(slot);
    if (!RECIPIENT_ROLES.includes(row.recipientRole)) {
      throw httpError(400, `Unsupported reward recipient: ${row.recipientRole}`);
    }
    if (!REWARD_TYPES.includes(row.rewardType)) {
      throw httpError(400, `Unsupported reward type: ${row.rewardType}`);
    }
    const amount = money(row.amount, "Reward amount");
    if (row.rewardType === "PERCENTAGE_COUPON" && Number(amount) > 100) {
      throw httpError(400, "Percentage discount cannot exceed 100");
    }
    const reward = {
      slot,
      recipientRole: row.recipientRole,
      rewardType: row.rewardType,
      amount,
      maxDiscount: null,
      minOrder: null,
      expiryDays: null,
      usageLimit: null,
      stackingMode: null,
    };
    if (row.rewardType === "PERCENTAGE_COUPON") {
      reward.maxDiscount = money(row.maxDiscount, "Maximum discount");
    } else if (row.maxDiscount != null && row.maxDiscount !== "") {
      reward.maxDiscount = money(row.maxDiscount, "Maximum discount");
    }
    if (row.minOrder != null && row.minOrder !== "") reward.minOrder = money(row.minOrder, "Minimum order", { allowZero: true });
    if (row.expiryDays != null && row.expiryDays !== "") {
      const days = Number(row.expiryDays);
      if (!Number.isInteger(days) || days < 1 || days > 3650) {
        throw httpError(400, "Reward expiry must be a whole number of days from 1 to 3650");
      }
      reward.expiryDays = days;
    }
    if (row.usageLimit != null && row.usageLimit !== "") {
      const limit = Number(row.usageLimit);
      if (!Number.isInteger(limit) || limit < 1 || limit > 1000000) {
        throw httpError(400, "Reward usage limit must be a whole number from 1 to 1000000");
      }
      reward.usageLimit = limit;
    }
    if (row.stackingMode != null && row.stackingMode !== "") {
      if (!STACKING_MODES.includes(row.stackingMode)) throw httpError(400, "Reward stacking mode is invalid");
      reward.stackingMode = row.stackingMode;
    }
    if (row.requireAdminApproval != null && row.requireAdminApproval !== "") {
      if (typeof row.requireAdminApproval !== "boolean") {
        throw httpError(400, "Reward approval must be true or false");
      }
      reward.requireAdminApproval = row.requireAdminApproval;
    }
    return reward;
  });
}

function parseBudget(body) {
  const source = body && typeof body === "object" ? body : {};
  const budget = {
    currency: "INR",
    amountCap: money(source.amountCap, "Campaign budget", { allowZero: true }),
    issuedAmount: "0.00",
    maxRewardCount: null,
    maxRewardAmount: null,
  };
  if (source.currency != null && source.currency !== "INR") {
    throw httpError(400, "Campaign budget currency must be INR");
  }
  if (source.maxRewardCount != null && source.maxRewardCount !== "") {
    const count = Number(source.maxRewardCount);
    if (!Number.isInteger(count) || count < 1 || count > 1000000) {
      throw httpError(400, "Maximum reward count must be a whole number from 1 to 1000000");
    }
    budget.maxRewardCount = count;
  }
  if (source.maxRewardAmount != null && source.maxRewardAmount !== "") {
    budget.maxRewardAmount = money(source.maxRewardAmount, "Maximum reward amount");
  }
  if (source.issuedAmount != null && Number(source.issuedAmount) !== 0) {
    throw httpError(400, "Budget consumption cannot be set from campaign configuration");
  }
  return budget;
}

function assertBudgetCoversRewards(budget, rewards) {
  if (!budget || !Array.isArray(rewards)) return;
  let reserved = 0;
  for (const reward of rewards) {
    if (reward.rewardType === "POINTS") continue;
    const cap = reward.rewardType === "PERCENTAGE_COUPON" ? Number(reward.maxDiscount) : Number(reward.amount);
    if (budget.maxRewardAmount && cap > Number(budget.maxRewardAmount)) {
      throw httpError(400, `Reward ${reward.slot} exceeds the maximum reward amount`);
    }
    reserved += cap;
  }
  if (reserved > Number(budget.amountCap)) {
    throw httpError(400, "Configured reward caps exceed the campaign budget");
  }
}

function parseRules(tree) {
  return validateRules(tree);
}

const REFERRAL_CATEGORIES = new Set(["REFERRAL", "BUYER_ACQUISITION", "SELLER_ACQUISITION"]);

function wholeNumber(value, label, min, max) {
  if (value == null || value === "") return { value: null };
  const parsed = typeof value === "string" ? Number(value.trim()) : value;
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    return { error: `${label} must be a whole number from ${min} to ${max}` };
  }
  return { value: parsed };
}

function inspectReferralPolicy(policy, { category, endsAt } = {}) {
  const failures = [];
  if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
    return {
      failures: [{ code: "REFERRAL_POLICY_INVALID", message: "Referral policy is required" }],
      policy: null,
    };
  }
  const days = wholeNumber(policy.codeExpiresInDays, "Referral code lifetime", 1, 3650);
  if (days.error) failures.push({ code: "REFERRAL_POLICY_INVALID", message: days.error });
  const hasEnd = endsAt != null && endsAt !== "" && !Number.isNaN(new Date(endsAt).getTime());
  if (!days.error && days.value == null && !hasEnd) {
    failures.push({
      code: "CODE_EXPIRY_REQUIRED",
      message: "A referral code needs a lifetime or a campaign end",
    });
  }
  const window = wholeNumber(policy.qualificationWindowDays, "Qualification window", 1, 3650);
  if (window.error) failures.push({ code: "REFERRAL_POLICY_INVALID", message: window.error });
  const attributions = wholeNumber(policy.maxAttributionsPerReferrer, "Referral attribution limit", 1, 1000000);
  if (attributions.error) failures.push({ code: "REFERRAL_POLICY_INVALID", message: attributions.error });
  const qualified = wholeNumber(policy.maxQualifiedPerReferrer, "Qualified referral limit", 1, 1000000);
  if (qualified.error) failures.push({ code: "REFERRAL_POLICY_INVALID", message: qualified.error });
  let requireAdminApproval = false;
  if (policy.requireAdminApproval != null && policy.requireAdminApproval !== "") {
    if (typeof policy.requireAdminApproval !== "boolean") {
      failures.push({ code: "REFERRAL_POLICY_INVALID", message: "Referral approval must be true or false" });
    } else {
      requireAdminApproval = policy.requireAdminApproval;
    }
  }
  const buyerRequired = category === "BUYER_ACQUISITION" || category === "REFERRAL";
  const buyer = policy.buyer && typeof policy.buyer === "object" && !Array.isArray(policy.buyer) ? policy.buyer : null;
  if (buyerRequired && !buyer) {
    failures.push({ code: "ATTRIBUTION_WINDOW_REQUIRED", message: "Buyer referral eligibility window is required" });
  }
  let buyerHours = null;
  if (buyer) {
    const hours = wholeNumber(buyer.maxAccountAgeHours, "Buyer account age", 1, 87600);
    if (hours.error) failures.push({ code: "ATTRIBUTION_WINDOW_REQUIRED", message: hours.error });
    else if (buyerRequired && hours.value == null) {
      failures.push({ code: "ATTRIBUTION_WINDOW_REQUIRED", message: "Buyer referral eligibility window is required" });
    } else {
      buyerHours = hours.value;
    }
  }
  const seller = policy.seller && typeof policy.seller === "object" && !Array.isArray(policy.seller) ? policy.seller : null;
  let sellerHours = null;
  if (policy.seller != null && !seller) {
    failures.push({ code: "REFERRAL_POLICY_INVALID", message: "Seller referral eligibility is invalid" });
  } else if (seller && seller.maxAccountAgeHours != null && seller.maxAccountAgeHours !== "") {
    const hours = wholeNumber(seller.maxAccountAgeHours, "Seller account age", 1, 87600);
    if (hours.error) failures.push({ code: "REFERRAL_POLICY_INVALID", message: hours.error });
    else sellerHours = hours.value;
  }
  if (failures.length > 0) return { failures, policy: null };
  return {
    failures: [],
    policy: {
      codeExpiresInDays: days.value,
      qualificationWindowDays: window.value,
      maxAttributionsPerReferrer: attributions.value,
      maxQualifiedPerReferrer: qualified.value,
      requireAdminApproval,
      buyer: buyer ? { maxAccountAgeHours: buyerHours } : null,
      seller: seller ? { maxAccountAgeHours: sellerHours } : null,
    },
  };
}

function parseReferralPolicy(policy, context) {
  if (!REFERRAL_CATEGORIES.has(context && context.category)) {
    throw httpError(400, "Referral policy applies to referral campaigns", "REFERRAL_POLICY_NOT_APPLICABLE");
  }
  const inspected = inspectReferralPolicy(policy, context);
  if (inspected.failures.length > 0) {
    const failure = inspected.failures[0];
    throw httpError(400, failure.message, failure.code);
  }
  return inspected.policy;
}

module.exports = {
  REFERRAL_CATEGORIES,
  assertBudgetCoversRewards,
  assertWindow,
  inspectReferralPolicy,
  parseAudiences,
  parseBudget,
  parseEligibility,
  parseHeader,
  parseReferralPolicy,
  parseRewards,
  parseRules,
  parseTriggers,
};
