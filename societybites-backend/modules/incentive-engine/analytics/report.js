const { httpError } = require("../lib/httpError");
const { cents, money } = require("../rewards/ledger");

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_RANGE_MS = 366 * DAY_MS;
const ISSUED = new Set(["ISSUED", "PARTIALLY_REDEEMED", "REDEEMED"]);
const REWARD_TYPES = ["FIXED_COUPON", "PERCENTAGE_COUPON", "PROMOTIONAL_CREDIT", "POINTS"];

const FAILURE_BUCKETS = Object.freeze({
  SELF_REFERRAL: "Self-referral",
  CODE_EXPIRED: "Expired code",
  ACCOUNT_NOT_ELIGIBLE: "Account age restriction",
  PRIOR_ACTIVITY: "Previous qualifying order",
  PRIOR_SELLER_ACTIVITY: "Previous qualifying order",
  PRIOR_LISTING: "Previous qualifying order",
  REFERRAL_LIMIT: "Referral cap reached",
  WINDOW_CLOSED: "Outside qualification window",
  REFERRAL_EXPIRED: "Outside qualification window",
  CAMPAIGN_NOT_ISSUABLE: "Campaign or audience ineligibility",
  CAMPAIGN_KIND_MISMATCH: "Campaign or audience ineligibility",
  CAMPAIGN_VERSION_UNPUBLISHED: "Campaign or audience ineligibility",
  ACQUISITION_MISMATCH: "Campaign or audience ineligibility",
  AUDIENCE_MISMATCH: "Campaign or audience ineligibility",
});

function parseRange(query = {}, now = new Date()) {
  const to = query.to ? new Date(query.to) : now;
  const from = query.from ? new Date(query.from) : new Date(to.getTime() - 30 * DAY_MS);
  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) {
    throw httpError(400, "Date range is invalid", "RANGE_INVALID");
  }
  if (from.getTime() > to.getTime()) throw httpError(400, "Date range is reversed", "RANGE_INVALID");
  if (to.getTime() - from.getTime() > MAX_RANGE_MS) {
    throw httpError(400, "Date range cannot exceed 366 days", "RANGE_TOO_WIDE");
  }
  return { from: from.toISOString(), to: to.toISOString() };
}

function asCents(value) {
  const parsed = cents(value);
  return parsed == null ? 0 : parsed;
}

function rate(part, whole) {
  if (!whole) return null;
  return Math.round((part / whole) * 1000) / 10;
}

function budgetView(configured, consumed) {
  const cap = asCents(configured);
  const used = asCents(consumed);
  const available = Math.max(0, cap - used);
  return {
    configured: money(cap),
    consumed: money(used),
    available: money(available),
    utilisationPercent: cap > 0 ? rate(used, cap) : null,
    exhausted: cap > 0 && used >= cap,
    scope: "current_version_counter",
    note: "Consumed includes amounts reserved for rewards that are waiting for approval. It is the budget counter, not a sum of the selected dates.",
  };
}

function remainingDuration(endsAt, now) {
  if (!endsAt) return { known: false, ended: false, hours: null };
  const end = new Date(endsAt);
  if (Number.isNaN(end.getTime())) return { known: false, ended: false, hours: null };
  const ms = end.getTime() - now.getTime();
  if (ms <= 0) return { known: true, ended: true, hours: 0 };
  return { known: true, ended: false, hours: Math.floor(ms / (60 * 60 * 1000)) };
}

function countOf(rows, predicate) {
  return (rows || []).reduce((total, row) => total + (predicate(row) ? Number(row.count) || 0 : 0), 0);
}

function shapePerformance(raw, now = new Date()) {
  const range = parseRange(raw.range || {}, now);
  const referrals = raw.referrals || {};
  const attributed = Number(referrals.attributed) || 0;
  const qualified = Number(referrals.qualified) || 0;
  const rewards = raw.rewards || [];
  const byType = {};
  for (const type of REWARD_TYPES) {
    byType[type] = {
      issued: countOf(rewards, (row) => row.rewardType === type && ISSUED.has(row.status)),
      pendingApproval: countOf(rewards, (row) => row.rewardType === type && row.status === "PENDING_APPROVAL"),
      rejected: countOf(rewards, (row) => row.rewardType === type && row.status === "REJECTED"),
      expired: countOf(rewards, (row) => row.rewardType === type && row.status === "EXPIRED"),
    };
  }
  const days = new Map();
  for (const row of raw.series || []) {
    const day = String(row.day);
    const current = days.get(day) || { day, attributed: 0, qualified: 0, issued: 0 };
    current.attributed += Number(row.attributed) || 0;
    current.qualified += Number(row.qualified) || 0;
    current.issued += Number(row.issued) || 0;
    days.set(day, current);
  }
  return {
    campaignId: raw.campaignId,
    range,
    referrals: {
      attributed,
      qualified,
      pending: Number(referrals.pending) || 0,
      conversionRate: rate(qualified, attributed),
    },
    rewards: {
      issued: countOf(rewards, (row) => ISSUED.has(row.status)),
      pendingApproval: Number(raw.pendingApprovalOpen) || 0,
      pendingApprovalScope: "current",
      rejected: countOf(rewards, (row) => row.status === "REJECTED"),
      expired: countOf(rewards, (row) => row.status === "EXPIRED"),
      byType,
    },
    budget: budgetView(raw.budget && raw.budget.configured, raw.budget && raw.budget.consumed),
    earlierVersionsIssued: money(asCents(raw.earlierVersionsIssued)),
    schedule: {
      status: raw.status || null,
      startsAt: raw.startsAt || null,
      endsAt: raw.endsAt || null,
      scheduledStart: raw.status === "SCHEDULED",
      remaining: remainingDuration(raw.endsAt, now),
    },
    series: [...days.values()].sort((left, right) => left.day.localeCompare(right.day)),
    timeline: (raw.timeline || []).map(presentAudit),
  };
}

function presentAudit(row) {
  const after = row && row.after && typeof row.after === "object" ? row.after : {};
  const before = row && row.before && typeof row.before === "object" ? row.before : {};
  return {
    id: row.id,
    action: row.action,
    actorId: row.actorId || null,
    createdAt: row.createdAt ? new Date(row.createdAt).toISOString() : null,
    before: pickAudit(before),
    after: pickAudit(after),
  };
}

function pickAudit(source) {
  const picked = {};
  for (const key of ["status", "versionId", "sourceCampaignId", "reason", "rewardId"]) {
    if (source[key] != null) picked[key] = source[key];
  }
  return picked;
}

function shapeReferralAnalytics(raw, now = new Date()) {
  const range = parseRange(raw.range || {}, now);
  const byKind = {};
  for (const kind of ["BUYER_ACQUISITION", "SELLER_ACQUISITION"]) {
    const rows = (raw.byKind || []).filter((row) => row.acquisitionKind === kind);
    const attributed = rows.reduce((total, row) => total + (Number(row.count) || 0), 0);
    const qualified = rows.filter((row) => row.status === "QUALIFIED").reduce((total, row) => total + (Number(row.count) || 0), 0);
    const pending = rows
      .filter((row) => row.status === "ATTRIBUTED" || row.status === "PENDING_REVIEW")
      .reduce((total, row) => total + (Number(row.count) || 0), 0);
    byKind[kind] = { attributed, qualified, pending, conversionRate: rate(qualified, attributed) };
  }
  const attributed = byKind.BUYER_ACQUISITION.attributed + byKind.SELLER_ACQUISITION.attributed;
  const qualified = byKind.BUYER_ACQUISITION.qualified + byKind.SELLER_ACQUISITION.qualified;
  const pending = byKind.BUYER_ACQUISITION.pending + byKind.SELLER_ACQUISITION.pending;
  return {
    range,
    campaignId: raw.campaignId || null,
    funnel: {
      codesGenerated: Number(raw.codesGenerated) || 0,
      codesAttributed: attributed,
      eligible: attributed,
      pendingQualification: pending,
      qualified,
      rewardsApproved: Number(raw.rewardsApproved) || 0,
      rewardsIssued: Number(raw.rewardsIssued) || 0,
    },
    comparison: byKind,
    failures: shapeFailures(raw.failureReasons || []),
    leaders: (raw.leaders || []).map(presentLeader),
    notes: {
      eligible: "Eligible is the number of referral rows that passed attribution. Rejected attempts are listed under failures and are not referral rows.",
      rewardsApproved: "Approval decisions recorded. A reward issued without an approval row is counted only under rewards issued.",
    },
  };
}

function shapeFailures(rows) {
  const buckets = {};
  for (const label of new Set(Object.values(FAILURE_BUCKETS))) buckets[label] = 0;
  const other = [];
  for (const row of rows) {
    const code = row && row.reason ? String(row.reason) : "UNRECORDED";
    const count = Number(row.count) || 0;
    const label = FAILURE_BUCKETS[code];
    if (label) {
      buckets[label] += count;
    } else {
      other.push({ reason: code, count });
    }
  }
  return {
    recorded: Object.entries(buckets).map(([reason, count]) => ({ reason, count })),
    other,
    note: "Counts include only reasons stored on a referral or an audit row. An attempt that was not stored is not given a count.",
  };
}

function presentLeader(row) {
  const name = row && typeof row.displayName === "string" && row.displayName.trim() ? row.displayName.trim() : "Member";
  return {
    displayName: name,
    qualified: Number(row && row.qualified) || 0,
    acquisitionKind: row && row.acquisitionKind ? row.acquisitionKind : null,
  };
}

function shapeRewardReport(raw, now = new Date()) {
  const range = parseRange(raw.range || {}, now);
  const counts = {};
  for (const status of ["PENDING_APPROVAL", "ISSUED", "PARTIALLY_REDEEMED", "REDEEMED", "EXPIRED", "REJECTED"]) {
    counts[status] = countOf(raw.statuses || [], (row) => row.status === status);
  }
  const byType = {};
  for (const type of REWARD_TYPES) {
    const rows = (raw.statuses || []).filter((row) => row.rewardType === type);
    byType[type] = {
      pendingApproval: countOf(rows, (row) => row.status === "PENDING_APPROVAL"),
      issued: countOf(rows, (row) => row.status === "ISSUED"),
      partiallyRedeemed: countOf(rows, (row) => row.status === "PARTIALLY_REDEEMED"),
      redeemed: countOf(rows, (row) => row.status === "REDEEMED"),
      expired: countOf(rows, (row) => row.status === "EXPIRED"),
      rejected: countOf(rows, (row) => row.status === "REJECTED"),
    };
  }
  const balances = raw.balances || {};
  return {
    range,
    campaignId: raw.campaignId || null,
    counts,
    byType,
    balances: {
      promotionalCredit: money(asCents(balances.promotionalCredit)),
      points: money(asCents(balances.points)),
      withdrawable: false,
    },
    expiring: raw.expiring || [],
    timeline: raw.timeline || [],
    nextCursor: raw.nextCursor || null,
    exceptions: {
      rejected: counts.REJECTED,
      budgetExhausted: Number(raw.budgetExhausted) || 0,
      issuedPastExpiry: Number(raw.issuedPastExpiry) || 0,
      note: "Exceptions are recorded rewards and audits. This report does not change a reward or the ledger.",
    },
  };
}

function shapeRisk(raw) {
  const failures = shapeFailures(raw.failureReasons || []);
  const self = (failures.recorded.find((row) => row.reason === "Self-referral") || {}).count || 0;
  const cap = (failures.recorded.find((row) => row.reason === "Referral cap reached") || {}).count || 0;
  const approaching = (raw.approachingCap || []).map((row) => ({
    displayName: row.displayName || "Member",
    userId: row.userId,
    attributed: Number(row.attributed) || 0,
    limit: row.limit == null ? null : Number(row.limit),
  }));
  return {
    indicators: [
      {
        code: "SELF_REFERRAL_ATTEMPTS",
        count: self,
        reviewRequired: self > 0,
        automaticAction: "none",
        detail: "Stored self-referral rejections. No account is blocked from this indicator.",
      },
      {
        code: "CAP_REACHED",
        count: cap,
        reviewRequired: cap > 0,
        automaticAction: "none",
        detail: "Stored attempts rejected because a referral cap was reached.",
      },
      {
        code: "CAP_APPROACHING",
        count: approaching.length,
        reviewRequired: approaching.length > 0,
        automaticAction: "none",
        referrers: approaching,
        detail: "Referrers at or above 80 percent of the configured attribution cap.",
      },
    ],
    sharedAccountPatterns: {
      detected: false,
      reason: "Referral records do not store a device or network identifier, so shared-account patterns are not inferred.",
    },
    note: "Indicators need a person to review them. They do not reject a reward or suspend a user.",
  };
}

function shapeAuditPage(raw) {
  const entries = (raw.entries || []).map(presentAudit);
  return { entries, nextCursor: raw.nextCursor || null };
}

module.exports = {
  FAILURE_BUCKETS,
  parseRange,
  presentLeader,
  shapeAuditPage,
  shapePerformance,
  shapeReferralAnalytics,
  shapeRewardReport,
  shapeRisk,
  qualificationNote,
};

function qualificationNote(row) {
  if (!row) return "This referral has no recorded status.";
  if (row.status === "QUALIFIED") return "This referral has qualified.";
  if (row.status === "PENDING_REVIEW") return "This referral is waiting for review before it can qualify.";
  if (row.status === "EXPIRED") return "The qualification window ended before this referral qualified.";
  if (row.status === "DISQUALIFIED") {
    if (row.disqualifyReason === "REFERRAL_LIMIT") return "The referral cap was reached.";
    if (row.disqualifyReason === "WINDOW_CLOSED" || row.disqualifyReason === "REFERRAL_EXPIRED") {
      return "This referral is outside the qualification window.";
    }
    return "This referral was disqualified.";
  }
  if (row.acquisitionKind === "SELLER_ACQUISITION") {
    const missing = [];
    if (!row.sellerEnabledAt) missing.push("seller terms");
    if (!row.listingId) missing.push("first listing publication");
    if (!row.qualifyingOrderId) missing.push("a first qualifying sale");
    if (missing.length) {
      return `Qualification is waiting for ${missing.join(", ")}. Milestones can arrive in any order.`;
    }
  }
  return "The referral is attributed and has not qualified yet.";
}
