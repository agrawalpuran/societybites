const { inspectReferralPolicy, REFERRAL_CATEGORIES } = require("./config");
const { AUDIENCE_KINDS, CONFIGURABLE_TRIGGERS } = require("../rules/catalog");

/**
 * Shared campaign readiness check.
 * Activation and simulation both use this. A future event processor must call
 * assessCampaign and must not treat evaluateRules(null) as eligibility.
 */

function rulesTreeReady(rules) {
  if (!rules || typeof rules !== "object" || Array.isArray(rules)) return false;
  if (Array.isArray(rules.conditions)) return rules.conditions.length > 0;
  return Boolean(rules.field && rules.operator);
}

function budgetReady(budget) {
  if (!budget || typeof budget !== "object" || Array.isArray(budget)) return false;
  const cap = Number(budget.amountCap);
  if (!Number.isFinite(cap) || cap < 0) return false;
  if (budget.currency && budget.currency !== "INR") return false;
  return true;
}

function assessCampaign(snapshot) {
  const source = snapshot && typeof snapshot === "object" ? snapshot : {};
  const audiences = Array.isArray(source.audiences) ? source.audiences : [];
  const triggers = Array.isArray(source.triggers) ? source.triggers : [];
  const rewards = Array.isArray(source.rewards) ? source.rewards : [];
  const failures = [];

  const explicitAllUsers = audiences.length === 1 && audiences[0] && audiences[0].kind === "ALL_USERS";
  if (audiences.length === 0) {
    failures.push({ code: "AUDIENCE_REQUIRED", message: "Add an audience before activation" });
  } else if (audiences.some((row) => row && row.kind === "ALL_USERS") && audiences.length > 1) {
    failures.push({ code: "AUDIENCE_COMBINATION", message: "ALL_USERS cannot be combined with another audience" });
  } else if (audiences.some((row) => !row || !AUDIENCE_KINDS.includes(row.kind))) {
    failures.push({ code: "AUDIENCE_INVALID", message: "Audience configuration is invalid" });
  }

  const policy = source.eligibility || null;
  if (policy !== "RULES" && policy !== "AUDIENCE_AND_TRIGGER_ONLY") {
    failures.push({ code: "ELIGIBILITY_REQUIRED", message: "Choose an eligibility policy before activation" });
  } else if (policy === "RULES" && !rulesTreeReady(source.rules)) {
    failures.push({ code: "RULES_REQUIRED", message: "Rules policy requires a non-empty rule tree" });
  } else if (policy === "AUDIENCE_AND_TRIGGER_ONLY" && source.rules) {
    failures.push({ code: "RULES_NOT_ALLOWED", message: "Audience and trigger policy does not take a rule tree" });
  }

  if (triggers.length === 0) {
    failures.push({ code: "TRIGGER_REQUIRED", message: "Add a trigger before activation" });
  } else if (triggers.some((row) => !row || !CONFIGURABLE_TRIGGERS.includes(row.eventType))) {
    failures.push({ code: "TRIGGER_INVALID", message: "Trigger configuration is invalid" });
  }

  if (rewards.length === 0) {
    failures.push({ code: "REWARD_REQUIRED", message: "Add a reward definition before activation" });
  } else if (rewards.some((row) => !row || !row.slot || !row.rewardType || !row.recipientRole || row.amount == null)) {
    failures.push({ code: "REWARD_INVALID", message: "Reward definition is invalid" });
  }

  if (!budgetReady(source.budget)) {
    failures.push({ code: "BUDGET_REQUIRED", message: "Add a budget before activation" });
  }

  if (REFERRAL_CATEGORIES.has(source.category)) {
    const policy = inspectReferralPolicy(source.referralPolicy, {
      category: source.category,
      endsAt: source.endsAt,
    });
    failures.push(...policy.failures);
  }

  const ready = failures.length === 0;
  return {
    ready,
    matchesEveryone: explicitAllUsers && ready,
    explicitAllUsers,
    policy: policy === "RULES" || policy === "AUDIENCE_AND_TRIGGER_ONLY" ? policy : null,
    failures,
  };
}

module.exports = { assessCampaign };
