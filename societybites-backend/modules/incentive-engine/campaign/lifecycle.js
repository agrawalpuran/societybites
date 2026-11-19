const { httpError } = require("../lib/httpError");
const { STATUSES } = require("../rules/catalog");

const TERMINAL = new Set(["COMPLETED", "EXPIRED", "TERMINATED"]);

function assertStatus(status) {
  if (!STATUSES.includes(status)) throw httpError(400, `Unsupported campaign status: ${status}`);
}

function activationTarget(campaign, now) {
  const startsAt = campaign.startsAt ? new Date(campaign.startsAt) : null;
  const endsAt = campaign.endsAt ? new Date(campaign.endsAt) : null;
  if (endsAt && endsAt <= now) throw httpError(400, "Campaign window has already ended");
  if (startsAt && startsAt > now) return "SCHEDULED";
  return "ACTIVE";
}

function assertCanActivate(flags) {
  if (!flags || flags.master !== true) {
    throw httpError(403, "Incentive engine is off", "ENGINE_DISABLED");
  }
}

function assertCategoryFlags(campaign, flags) {
  const referralCategories = new Set(["REFERRAL", "BUYER_ACQUISITION", "SELLER_ACQUISITION"]);
  const promotionalCategories = new Set(["PROMOTIONAL", "FESTIVE"]);
  if (referralCategories.has(campaign.category) && flags.referral !== true) {
    throw httpError(403, "Referral campaigns are off", "REFERRAL_DISABLED");
  }
  if (promotionalCategories.has(campaign.category) && flags.promotional !== true) {
    throw httpError(403, "Promotional campaigns are off", "PROMOTIONAL_DISABLED");
  }
}

function assertTransition(from, to) {
  assertStatus(from);
  assertStatus(to);
  const allowed = {
    DRAFT: ["SCHEDULED", "ACTIVE", "TERMINATED"],
    SCHEDULED: ["ACTIVE", "PAUSED", "EXPIRED", "TERMINATED"],
    ACTIVE: ["PAUSED", "COMPLETED", "EXPIRED", "TERMINATED"],
    PAUSED: ["ACTIVE", "SCHEDULED", "COMPLETED", "EXPIRED", "TERMINATED"],
    COMPLETED: [],
    EXPIRED: [],
    TERMINATED: [],
  };
  if (!allowed[from].includes(to)) {
    throw httpError(409, `Cannot move a campaign from ${from} to ${to}`);
  }
}

module.exports = {
  TERMINAL,
  activationTarget,
  assertCanActivate,
  assertCategoryFlags,
  assertTransition,
};
