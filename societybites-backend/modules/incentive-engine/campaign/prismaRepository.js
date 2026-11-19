const { httpError } = require("../lib/httpError");

const versionInclude = {
  audiences: true,
  triggers: true,
  rules: { orderBy: { sortOrder: "asc" } },
  rewardDefinitions: true,
  budget: true,
};

function storageError(error) {
  if (error && error.statusCode) return error;
  if (
    error &&
    (error.code === "P2021" ||
      error.code === "P2022" ||
      error instanceof TypeError)
  ) {
    return httpError(503, "Incentive storage is not available", "INCENTIVE_STORAGE_UNAVAILABLE");
  }
  return error;
}

async function guard(work) {
  try {
    return await work();
  } catch (error) {
    throw storageError(error);
  }
}

function model(prisma, name) {
  const delegate = prisma && prisma[name];
  if (!delegate) {
    throw httpError(503, "Incentive storage is not available", "INCENTIVE_STORAGE_UNAVAILABLE");
  }
  return delegate;
}

function toApiVersion(row) {
  if (!row) return null;
  return {
    id: row.id,
    campaignId: row.campaignId,
    versionNumber: row.versionNumber,
    snapshot: row.snapshot,
    publishedAt: row.publishedAt ? new Date(row.publishedAt).toISOString() : null,
    publishedBy: row.publishedBy || null,
    createdAt: row.createdAt ? new Date(row.createdAt).toISOString() : null,
    audiences: row.snapshot && row.snapshot.audiences ? row.snapshot.audiences : [],
    triggers: row.snapshot && row.snapshot.triggers ? row.snapshot.triggers : [],
    rules: row.rules || [],
    rewards: row.snapshot && row.snapshot.rewards ? row.snapshot.rewards : [],
    budget: row.snapshot ? row.snapshot.budget : null,
  };
}

function toApiCampaign(row) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    category: row.category,
    status: row.status,
    priority: row.priority,
    stackingMode: row.stackingMode,
    startsAt: row.startsAt ? new Date(row.startsAt).toISOString() : null,
    endsAt: row.endsAt ? new Date(row.endsAt).toISOString() : null,
    currentVersionId: row.currentVersionId,
    createdBy: row.createdBy,
    createdAt: row.createdAt ? new Date(row.createdAt).toISOString() : null,
    updatedAt: row.updatedAt ? new Date(row.updatedAt).toISOString() : null,
  };
}

async function writeChildren(tx, versionId, version) {
  await tx.incentiveAudience.deleteMany({ where: { versionId } });
  await tx.incentiveTrigger.deleteMany({ where: { versionId } });
  await tx.incentiveRule.deleteMany({ where: { versionId } });
  await tx.incentiveRewardDefinition.deleteMany({ where: { versionId } });
  await tx.incentiveBudget.deleteMany({ where: { versionId } });
  const snapshot = version.snapshot || {};
  if (Array.isArray(snapshot.audiences) && snapshot.audiences.length) {
    await tx.incentiveAudience.createMany({
      data: snapshot.audiences.map((row) => ({
        versionId,
        kind: row.kind,
        payload: row.payload || {},
      })),
    });
  }
  if (Array.isArray(version.triggers) && version.triggers.length) {
    await tx.incentiveTrigger.createMany({
      data: version.triggers.map((row) => ({ versionId, eventType: row.eventType })),
    });
  }
  if (Array.isArray(version.rules) && version.rules.length) {
    await tx.incentiveRule.createMany({
      data: version.rules.map((row) => ({
        versionId,
        groupKey: row.groupKey,
        parentGroupKey: row.parentGroupKey,
        combinator: row.combinator,
        field: row.field,
        operator: row.operator,
        value: row.value === undefined ? null : row.value,
        sortOrder: row.sortOrder,
      })),
    });
  }
  if (Array.isArray(snapshot.rewards) && snapshot.rewards.length) {
    await tx.incentiveRewardDefinition.createMany({
      data: snapshot.rewards.map((row) => ({
        versionId,
        slot: row.slot,
        recipientRole: row.recipientRole,
        rewardType: row.rewardType,
        amount: row.amount,
        maxDiscount: row.maxDiscount,
        minOrder: row.minOrder,
        expiryDays: row.expiryDays,
        usageLimit: row.usageLimit,
        stackingMode: row.stackingMode,
        config: row.requireAdminApproval === true ? { requireAdminApproval: true } : {},
      })),
    });
  }
  if (snapshot.budget) {
    await tx.incentiveBudget.create({
      data: {
        versionId,
        currency: snapshot.budget.currency || "INR",
        amountCap: snapshot.budget.amountCap,
        issuedAmount: "0.00",
      },
    });
  }
}

function createPrismaRepository(prisma) {
  return {
    async createCampaign(row) {
      return guard(async () => {
        const created = await model(prisma, "incentiveCampaign").create({
          data: {
            name: row.name,
            description: row.description,
            category: row.category,
            status: "DRAFT",
            priority: row.priority,
            stackingMode: row.stackingMode,
            startsAt: row.startsAt,
            endsAt: row.endsAt,
            createdBy: row.createdBy,
          },
        });
        return toApiCampaign(created);
      });
    },
    async listCampaigns() {
      return guard(async () => {
        const rows = await model(prisma, "incentiveCampaign").findMany({ orderBy: { createdAt: "desc" } });
        return rows.map(toApiCampaign);
      });
    },
    async getCampaign(id) {
      return guard(async () => toApiCampaign(await model(prisma, "incentiveCampaign").findUnique({ where: { id } })));
    },
    async saveCampaign(campaign) {
      return guard(async () => {
        const saved = await model(prisma, "incentiveCampaign").update({
          where: { id: campaign.id },
          data: {
            name: campaign.name,
            description: campaign.description,
            category: campaign.category,
            status: campaign.status,
            priority: campaign.priority,
            stackingMode: campaign.stackingMode,
            startsAt: campaign.startsAt,
            endsAt: campaign.endsAt,
            currentVersionId: campaign.currentVersionId,
          },
        });
        return toApiCampaign(saved);
      });
    },
    async createVersion(version) {
      return guard(() =>
        prisma.$transaction(async (tx) => {
          const created = await tx.incentiveCampaignVersion.create({
            data: {
              campaignId: version.campaignId,
              versionNumber: version.versionNumber,
              snapshot: version.snapshot,
            },
          });
          await writeChildren(tx, created.id, version);
          const full = await tx.incentiveCampaignVersion.findUnique({
            where: { id: created.id },
            include: versionInclude,
          });
          return toApiVersion(full);
        })
      );
    },
    async saveVersion(version) {
      return guard(() =>
        prisma.$transaction(async (tx) => {
          const existing = await tx.incentiveCampaignVersion.findUnique({ where: { id: version.id } });
          if (!existing) throw httpError(404, "Campaign version not found");
          if (existing.publishedAt) throw httpError(409, "Published campaign versions are immutable");
          await tx.incentiveCampaignVersion.update({
            where: { id: version.id },
            data: {
              snapshot: version.snapshot,
              publishedAt: version.publishedAt,
              publishedBy: version.publishedBy,
            },
          });
          if (!version.publishedAt) await writeChildren(tx, version.id, version);
          const full = await tx.incentiveCampaignVersion.findUnique({
            where: { id: version.id },
            include: versionInclude,
          });
          return toApiVersion(full);
        })
      );
    },
    async listVersions(campaignId) {
      return guard(async () => {
        const rows = await model(prisma, "incentiveCampaignVersion").findMany({
          where: { campaignId },
          orderBy: { versionNumber: "asc" },
          include: versionInclude,
        });
        return rows.map(toApiVersion);
      });
    },
    async getVersion(id) {
      return guard(async () =>
        toApiVersion(
          await model(prisma, "incentiveCampaignVersion").findUnique({
            where: { id },
            include: versionInclude,
          })
        )
      );
    },
    async appendAudit(row) {
      return guard(async () => {
        await model(prisma, "incentiveAuditLog").create({
          data: {
            actorId: row.actorId || "system",
            action: row.action,
            campaignId: row.campaignId,
            before: row.before === undefined ? null : row.before,
            after: row.after === undefined ? null : row.after,
          },
        });
      });
    },
  };
}

module.exports = { createPrismaRepository };
