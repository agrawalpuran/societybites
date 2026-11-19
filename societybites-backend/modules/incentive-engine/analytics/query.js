const { Prisma } = require("@prisma/client");
const { httpError } = require("../lib/httpError");
const { parseRange, shapeAuditPage, shapePerformance, shapeReferralAnalytics, shapeRewardReport, shapeRisk } = require("./report");

const PAGE = 20;
const LIFECYCLE_ACTIONS = [
  "CAMPAIGN_CREATED",
  "CAMPAIGN_UPDATED",
  "CAMPAIGN_DUPLICATED",
  "CAMPAIGN_VERSION_FORKED",
  "CAMPAIGN_ACTIVATED",
  "CAMPAIGN_PAUSED",
  "CAMPAIGN_TERMINATED",
  "CAMPAIGN_COMPLETED",
  "CAMPAIGN_EXPIRED",
  "CAMPAIGN_BUDGET_SET",
  "CAMPAIGN_AUDIENCE_SET",
  "CAMPAIGN_TRIGGERS_SET",
  "CAMPAIGN_RULES_SET",
  "CAMPAIGN_REWARDS_SET",
  "CAMPAIGN_REFERRAL_POLICY_SET",
  "REWARD_APPROVED",
  "REWARD_REJECTED",
  "REWARD_PENDING",
  "REWARD_ISSUED",
  "REWARD_BUDGET_EXHAUSTED",
  "REWARD_REDEEMED",
  "REWARD_EXPIRED",
];

function campaignFilter(campaignId) {
  return campaignId ? { campaignId: String(campaignId) } : {};
}

function rangeWhere(range) {
  return { gte: new Date(range.from), lt: new Date(range.to) };
}

async function versionIds(prisma, campaignId) {
  const versions = await prisma.incentiveCampaignVersion.findMany({
    where: { campaignId },
    select: { id: true, versionNumber: true },
    orderBy: { versionNumber: "desc" },
  });
  return versions.map((row) => row.id);
}

async function performance(prisma, { campaignId, query, now }) {
  const campaign = await prisma.incentiveCampaign.findUnique({ where: { id: campaignId } });
  if (!campaign) throw httpError(404, "Campaign not found");
  const range = parseRange(query, now);
  const created = rangeWhere(range);
  const ids = await versionIds(prisma, campaignId);
  const currentVersionId = campaign.currentVersionId;
  const [referralGroups, rewardGroups, budgets, seriesReferrals, seriesRewards, timeline, pendingApprovalOpen] = await Promise.all([
    prisma.incentiveReferral.groupBy({
      by: ["status"],
      where: { campaignId, attributedAt: created },
      _count: { _all: true },
    }),
    ids.length
      ? prisma.incentiveReward.groupBy({
          by: ["status", "campaignVersionId", "rewardSlot"],
          where: { campaignVersionId: { in: ids }, createdAt: created },
          _count: { _all: true },
        })
      : [],
    ids.length
      ? prisma.incentiveBudget.findMany({ where: { versionId: { in: ids } } })
      : [],
    prisma.$queryRaw`
      SELECT to_char(date_trunc('day', "attributedAt"), 'YYYY-MM-DD') AS day,
             COUNT(*)::int AS attributed,
             COUNT(*) FILTER (WHERE status = 'QUALIFIED')::int AS qualified
      FROM "IncentiveReferral"
      WHERE "campaignId" = ${campaignId}
        AND "attributedAt" >= ${new Date(range.from)}
        AND "attributedAt" < ${new Date(range.to)}
      GROUP BY 1
      ORDER BY 1
    `,
    ids.length
      ? prisma.$queryRaw`
          SELECT to_char(date_trunc('day', "createdAt"), 'YYYY-MM-DD') AS day,
                 COUNT(*)::int AS issued
          FROM "IncentiveReward"
          WHERE "campaignVersionId" IN (${Prisma.join(ids)})
            AND status IN ('ISSUED', 'PARTIALLY_REDEEMED', 'REDEEMED')
            AND "createdAt" >= ${new Date(range.from)}
            AND "createdAt" < ${new Date(range.to)}
          GROUP BY 1
          ORDER BY 1
        `
      : [],
    prisma.incentiveAuditLog.findMany({
      where: { campaignId, action: { in: LIFECYCLE_ACTIONS } },
      orderBy: { createdAt: "desc" },
      take: 50,
      select: { id: true, action: true, actorId: true, createdAt: true, before: true, after: true },
    }),
    ids.length
      ? prisma.incentiveReward.count({ where: { campaignVersionId: { in: ids }, status: "PENDING_APPROVAL" } })
      : 0,
  ]);
  const definitions = rewardGroups.length
    ? await prisma.incentiveRewardDefinition.findMany({
        where: {
          OR: rewardGroups.map((row) => ({ versionId: row.campaignVersionId, slot: row.rewardSlot })),
        },
        select: { versionId: true, slot: true, rewardType: true },
      })
    : [];
  const typeBySlot = new Map(definitions.map((row) => [`${row.versionId}:${row.slot}`, row.rewardType]));
  const currentBudget = budgets.find((row) => row.versionId === currentVersionId);
  const earlier = budgets
    .filter((row) => row.versionId !== currentVersionId)
    .reduce((total, row) => total + Number(row.issuedAmount || 0), 0);
  const referralCount = (status) => {
    const found = referralGroups.find((row) => row.status === status);
    return found ? found._count._all : 0;
  };
  return shapePerformance({
    campaignId,
    range: query,
    status: campaign.status,
    startsAt: campaign.startsAt,
    endsAt: campaign.endsAt,
    referrals: {
      attributed: referralGroups.reduce((total, row) => total + row._count._all, 0),
      qualified: referralCount("QUALIFIED"),
      pending: referralCount("ATTRIBUTED") + referralCount("PENDING_REVIEW"),
    },
    rewards: rewardGroups.map((row) => ({
      status: row.status,
      rewardType: typeBySlot.get(`${row.campaignVersionId}:${row.rewardSlot}`) || null,
      count: row._count._all,
    })),
    pendingApprovalOpen,
    budget: currentBudget
      ? { configured: currentBudget.amountCap, consumed: currentBudget.issuedAmount }
      : { configured: "0.00", consumed: "0.00" },
    earlierVersionsIssued: earlier.toFixed(2),
    series: [
      ...seriesReferrals.map((row) => ({ day: row.day, attributed: row.attributed, qualified: row.qualified, issued: 0 })),
      ...seriesRewards.map((row) => ({ day: row.day, attributed: 0, qualified: 0, issued: row.issued })),
    ],
    timeline,
  }, now);
}

async function referralAnalytics(prisma, { query, now }) {
  const range = parseRange(query, now);
  const created = rangeWhere(range);
  const campaignId = query && query.campaignId ? String(query.campaignId) : "";
  const referralWhere = { attributedAt: created, ...campaignFilter(campaignId) };
  const codeWhere = { createdAt: created, ...(campaignId ? { campaignId } : {}) };
  const [codesGenerated, byKind, failures, leaders, rewardsApproved, rewardsIssued] = await Promise.all([
    prisma.incentiveReferralCode.count({ where: codeWhere }),
    prisma.incentiveReferral.groupBy({
      by: ["acquisitionKind", "status"],
      where: referralWhere,
      _count: { _all: true },
    }),
    failureReasons(prisma, { campaignId, created }),
    leaderboard(prisma, { campaignId, acquisitionKind: query && query.audience, createdAt: created }),
    prisma.incentiveApproval.count({
      where: {
        decision: "APPROVED",
        createdAt: created,
        ...(campaignId
          ? { reward: { campaignVersion: { campaignId } } }
          : {}),
      },
    }),
    prisma.incentiveReward.count({
      where: {
        status: { in: ["ISSUED", "PARTIALLY_REDEEMED", "REDEEMED"] },
        createdAt: created,
        ...(campaignId ? { campaignVersion: { campaignId } } : {}),
      },
    }),
  ]);
  return shapeReferralAnalytics({
    range: query,
    campaignId: campaignId || null,
    codesGenerated,
    byKind: byKind.map((row) => ({ acquisitionKind: row.acquisitionKind, status: row.status, count: row._count._all })),
    failureReasons: failures,
    leaders,
    rewardsApproved,
    rewardsIssued,
  }, now);
}

async function failureReasons(prisma, { campaignId, created }) {
  const campaignSql = campaignId ? Prisma.sql`AND "campaignId" = ${campaignId}` : Prisma.empty;
  const rows = await prisma.$queryRaw`
    SELECT COALESCE("after"->>'reason', "disqualifyReason", "action") AS reason,
           COUNT(*)::int AS count
    FROM (
      SELECT "action", "after", NULL::text AS "disqualifyReason"
      FROM "IncentiveAuditLog"
      WHERE "createdAt" >= ${created.gte}
        AND "createdAt" < ${created.lt}
        AND "action" IN (
          'REFERRAL_CLAIM_REJECTED',
          'REFERRAL_QUALIFICATION_SKIPPED',
          'REFERRAL_DISQUALIFIED',
          'REFERRAL_REJECTED',
          'REFERRAL_EXPIRED'
        )
        ${campaignSql}
      UNION ALL
      SELECT 'REFERRAL_STATUS' AS action, NULL::jsonb AS after, "disqualifyReason"
      FROM "IncentiveReferral"
      WHERE "attributedAt" >= ${created.gte}
        AND "attributedAt" < ${created.lt}
        AND "disqualifyReason" IS NOT NULL
        ${campaignSql}
    ) reasons
    GROUP BY 1
    ORDER BY 2 DESC
  `;
  return rows.map((row) => ({ reason: row.reason, count: row.count }));
}

async function leaderboard(prisma, { campaignId, acquisitionKind, createdAt }) {
  const where = { status: "QUALIFIED" };
  if (createdAt) where.qualifiedAt = createdAt;
  if (campaignId) where.campaignId = campaignId;
  if (acquisitionKind === "BUYER" || acquisitionKind === "BUYER_ACQUISITION") where.acquisitionKind = "BUYER_ACQUISITION";
  if (acquisitionKind === "SELLER" || acquisitionKind === "SELLER_ACQUISITION") where.acquisitionKind = "SELLER_ACQUISITION";
  const grouped = await prisma.incentiveReferral.groupBy({
    by: ["referrerUserId", "acquisitionKind"],
    where,
    _count: { _all: true },
    orderBy: { _count: { referrerUserId: "desc" } },
    take: 20,
  });
  const ids = [...new Set(grouped.map((row) => row.referrerUserId))];
  const names = ids.length
    ? await prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } })
    : [];
  return grouped.map((row) => ({
    userId: row.referrerUserId,
    displayName: (names.find((user) => user.id === row.referrerUserId) || {}).name || "Member",
    qualified: row._count._all,
    acquisitionKind: row.acquisitionKind,
  }));
}

async function rewardReport(prisma, { query, now }) {
  const range = parseRange(query, now);
  const created = rangeWhere(range);
  const campaignId = query && query.campaignId ? String(query.campaignId) : "";
  const where = { createdAt: created };
  if (campaignId) where.campaignVersion = { campaignId };
  if (query && query.status) where.status = String(query.status);
  const groups = await prisma.incentiveReward.groupBy({
    by: ["status", "campaignVersionId", "rewardSlot"],
    where,
    _count: { _all: true },
  });
  const definitions = groups.length
    ? await prisma.incentiveRewardDefinition.findMany({
        where: { OR: groups.map((row) => ({ versionId: row.campaignVersionId, slot: row.rewardSlot })) },
        select: { versionId: true, slot: true, rewardType: true },
      })
    : [];
  const typeBySlot = new Map(definitions.map((row) => [`${row.versionId}:${row.slot}`, row.rewardType]));
  const requestedType = query && query.rewardType ? String(query.rewardType) : "";
  let statuses = groups.map((row) => ({
    status: row.status,
    rewardType: typeBySlot.get(`${row.campaignVersionId}:${row.rewardSlot}`) || null,
    count: row._count._all,
  }));
  if (requestedType) statuses = statuses.filter((row) => row.rewardType === requestedType);
  const balances = await ledgerBalances(prisma, { campaignId, created });
  const expiring = await prisma.incentiveReward.findMany({
    where: {
      ...where,
      expiresAt: { gt: new Date() },
      status: { in: ["ISSUED", "PARTIALLY_REDEEMED", "PENDING_APPROVAL"] },
    },
    orderBy: { expiresAt: "asc" },
    take: PAGE,
    select: {
      id: true,
      status: true,
      amount: true,
      currency: true,
      expiresAt: true,
      campaignVersionId: true,
      rewardSlot: true,
    },
  });
  const cursor = query && query.cursor ? String(query.cursor) : null;
  const timelineWhere = { createdAt: created };
  if (cursor) {
    const current = await prisma.incentiveLedgerEntry.findUnique({ where: { id: cursor }, select: { id: true, createdAt: true } });
    if (current) {
      timelineWhere.OR = [
        { createdAt: { lt: current.createdAt } },
        { createdAt: current.createdAt, id: { lt: current.id } },
      ];
    }
  }
  if (campaignId) timelineWhere.reward = { campaignVersion: { campaignId } };
  const timelineRows = await prisma.incentiveLedgerEntry.findMany({
    where: timelineWhere,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: PAGE + 1,
    select: { id: true, entryType: true, amount: true, currency: true, createdAt: true, rewardId: true },
  });
  const timelinePage = timelineRows.slice(0, PAGE);
  const [budgetExhausted, issuedPastExpiry] = await Promise.all([
    prisma.incentiveAuditLog.count({
      where: { action: "REWARD_BUDGET_EXHAUSTED", createdAt: created, ...campaignFilter(campaignId) },
    }),
    prisma.incentiveReward.count({
      where: {
        status: { in: ["ISSUED", "PARTIALLY_REDEEMED"] },
        expiresAt: { lt: new Date() },
        ...(campaignId ? { campaignVersion: { campaignId } } : {}),
      },
    }),
  ]);
  return shapeRewardReport({
    range: query,
    campaignId: campaignId || null,
    statuses,
    balances,
    expiring: expiring.map((row) => ({
      id: row.id,
      status: row.status,
      rewardType: typeBySlot.get(`${row.campaignVersionId}:${row.rewardSlot}`) || null,
      amount: String(row.amount),
      currency: row.currency,
      expiresAt: row.expiresAt ? row.expiresAt.toISOString() : null,
    })),
    timeline: timelinePage.map((row) => ({
      id: row.id,
      entryType: row.entryType,
      amount: String(row.amount),
      currency: row.currency,
      createdAt: row.createdAt.toISOString(),
      rewardId: row.rewardId,
    })),
    nextCursor: timelineRows.length > PAGE ? timelinePage[timelinePage.length - 1].id : null,
    budgetExhausted,
    issuedPastExpiry,
  }, now);
}

async function ledgerBalances(prisma, { campaignId, created }) {
  const campaignSql = campaignId ? Prisma.sql`AND v."campaignId" = ${campaignId}` : Prisma.empty;
  const rows = await prisma.$queryRaw`
    SELECT d."rewardType" AS type, COALESCE(SUM(e."amount"), 0) AS amount
    FROM "IncentiveLedgerEntry" e
    JOIN "IncentiveReward" r ON r.id = e."rewardId"
    JOIN "IncentiveCampaignVersion" v ON v.id = r."campaignVersionId"
    JOIN "IncentiveRewardDefinition" d ON d."versionId" = r."campaignVersionId" AND d.slot = r."rewardSlot"
    WHERE e."createdAt" >= ${created.gte}
      AND e."createdAt" < ${created.lt}
      AND d."rewardType" IN ('PROMOTIONAL_CREDIT', 'POINTS')
      ${campaignSql}
    GROUP BY d."rewardType"
  `;
  const found = Object.fromEntries(rows.map((row) => [row.type, row.amount]));
  return {
    promotionalCredit: found.PROMOTIONAL_CREDIT || 0,
    points: found.POINTS || 0,
  };
}

async function auditPage(prisma, { query }) {
  const range = parseRange(query);
  const where = { createdAt: rangeWhere(range) };
  if (query && query.campaignId) where.campaignId = String(query.campaignId);
  if (query && query.action) where.action = String(query.action);
  if (query && query.cursor) {
    const current = await prisma.incentiveAuditLog.findUnique({
      where: { id: String(query.cursor) },
      select: { id: true, createdAt: true },
    });
    if (current) {
      where.AND = [{
        OR: [
          { createdAt: { lt: current.createdAt } },
          { createdAt: current.createdAt, id: { lt: current.id } },
        ],
      }];
    }
  }
  const rows = await prisma.incentiveAuditLog.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: PAGE + 1,
    select: { id: true, action: true, actorId: true, createdAt: true, before: true, after: true },
  });
  const entries = rows.slice(0, PAGE);
  return shapeAuditPage({
    entries,
    nextCursor: rows.length > PAGE ? entries[entries.length - 1].id : null,
  });
}

async function risk(prisma, { query, now }) {
  const range = parseRange(query, now);
  const created = rangeWhere(range);
  const campaignId = query && query.campaignId ? String(query.campaignId) : "";
  const reasons = await failureReasons(prisma, { campaignId, created });
  let approachingCap = [];
  if (campaignId) {
    const campaign = await prisma.incentiveCampaign.findUnique({ where: { id: campaignId } });
    const version = campaign && campaign.currentVersionId
      ? await prisma.incentiveCampaignVersion.findUnique({ where: { id: campaign.currentVersionId } })
      : null;
    const limit = version && version.snapshot && version.snapshot.referralPolicy
      ? version.snapshot.referralPolicy.maxAttributionsPerReferrer
      : null;
    if (Number.isInteger(limit) && limit > 0) {
      const grouped = await prisma.incentiveReferral.groupBy({
        by: ["referrerUserId"],
        where: { campaignId },
        _count: { _all: true },
      });
      const near = grouped.filter((row) => row._count._all >= Math.ceil(limit * 0.8));
      const ids = near.map((row) => row.referrerUserId);
      const names = ids.length
        ? await prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } })
        : [];
      approachingCap = near.map((row) => ({
        userId: row.referrerUserId,
        displayName: (names.find((user) => user.id === row.referrerUserId) || {}).name || "Member",
        attributed: row._count._all,
        limit,
      }));
    }
  }
  return shapeRisk({ failureReasons: reasons, approachingCap });
}

module.exports = {
  auditPage,
  leaderboard,
  performance,
  referralAnalytics,
  rewardReport,
  risk,
};
