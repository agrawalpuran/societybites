const crypto = require("crypto");
const { effectiveFlags, flagsOff, readFlags } = require("../configuration/flags");
const { isDue, leaseExpired } = require("./lifecycle");
const { ORDER_TERMINAL_TYPES } = require("./validate");

const ORDER_TERMINAL_INDEX = "IncentiveEvent_one_terminal_order_event";

function listedFields(value) {
  if (Array.isArray(value)) return value.map((field) => String(field));
  if (typeof value !== "string" || !value) return [];
  const wrapped = value.match(/fields:\s*\(([^)]*)\)/);
  const source = wrapped ? wrapped[1] : value;
  return source.split(",").map((field) => field.replace(/[`\s"]/g, "")).filter(Boolean);
}

/**
 * Prisma 5.22 reports this partial index as the indexed column `entityId`.
 * The eventId unique constraint is reported separately as `eventId`.
 * Other unique violations stay untouched.
 */
function conflictError(error) {
  if (!error || error.code !== "P2002") return null;
  const meta = error.meta || {};
  if (meta.modelName && meta.modelName !== "IncentiveEvent") return null;
  const described = [meta.constraint, meta.target, error.message]
    .map((part) => (typeof part === "string" ? part : JSON.stringify(part || "")))
    .join(" ");
  const fields = listedFields(meta.target).length > 0 ? listedFields(meta.target) : listedFields(error.message);
  let constraint = null;
  if (described.includes(ORDER_TERMINAL_INDEX) || described.includes("one_terminal_order")) {
    constraint = "orderTerminal";
  } else if (fields.length === 1 && fields[0] === "entityId") {
    constraint = "orderTerminal";
  } else if (fields.length === 1 && (fields[0] === "eventId" || fields[0].endsWith("_eventId_key"))) {
    constraint = "eventId";
  }
  if (!constraint) return null;
  const wrapped = new Error(error.message);
  wrapped.code = "P2002";
  wrapped.constraint = constraint;
  wrapped.meta = error.meta;
  return wrapped;
}

function createPrismaEventRepository(prisma) {
  return {
    async readFlags() {
      return readFlags({
        loadRows: () => prisma.incentiveSetting.findMany({ select: { key: true, value: true } }),
      });
    },

    async findById(id) {
      return prisma.incentiveEvent.findUnique({ where: { id } });
    },

    async findByEventId(eventId) {
      return prisma.incentiveEvent.findUnique({ where: { eventId } });
    },

    async findOrderTerminal(entityId) {
      return prisma.incentiveEvent.findFirst({
        where: { entityType: "order", entityId, type: { in: ORDER_TERMINAL_TYPES } },
      });
    },

    async insertEvent(row) {
      try {
        return await prisma.incentiveEvent.create({ data: row });
      } catch (error) {
        const conflict = conflictError(error);
        if (conflict) throw conflict;
        throw error;
      }
    },

    async findDue(now, limit) {
      return prisma.incentiveEvent.findMany({
        where: {
          status: { in: ["PENDING", "FAILED"] },
          OR: [{ nextAttemptAt: null }, { nextAttemptAt: { lte: now } }],
        },
        orderBy: { createdAt: "asc" },
        take: limit,
      });
    },

    async claim(id, { now, workerId }) {
      const token = crypto.randomUUID();
      const claimedBy = workerId || null;
      // Master and eligibility are one statement. A switch committed before this UPDATE cannot be missed.
      const updated = await prisma.$executeRaw`
        UPDATE "IncentiveEvent" AS e
        SET
          "status" = 'PROCESSING',
          "attempts" = e."attempts" + 1,
          "claimToken" = ${token},
          "claimedAt" = ${now},
          "claimedBy" = ${claimedBy},
          "lastError" = NULL
        WHERE e."id" = ${id}
          AND e."status" IN ('PENDING', 'FAILED')
          AND (e."nextAttemptAt" IS NULL OR e."nextAttemptAt" <= ${now})
          AND EXISTS (
            SELECT 1
            FROM "IncentiveSetting" AS s
            WHERE s."key" = 'master_enabled'
              AND btrim(s."value", E' \\t\\n\\r\\f\\v') = 'true'
          )
      `;
      let flags;
      try {
        const rows = await prisma.incentiveSetting.findMany({ select: { key: true, value: true } });
        flags = effectiveFlags(rows);
      } catch (error) {
        return { blocked: true, flags: flagsOff() };
      }
      if (Number(updated) !== 1) {
        if (flags.master !== true) return { blocked: true, flags };
        return { claimed: false, flags };
      }
      const event = await prisma.incentiveEvent.findUnique({ where: { id } });
      if (!event || event.claimToken !== token) return { claimed: false, flags };
      return { claimed: true, event, token, flags };
    },

    async finish(id, token, patch) {
      return prisma.$transaction(async (tx) => {
        const updated = await tx.incentiveEvent.updateMany({
          where: { id, status: "PROCESSING", claimToken: token },
          data: {
            status: patch.status,
            claimToken: null,
            claimedAt: null,
            claimedBy: null,
            nextAttemptAt: patch.nextAttemptAt || null,
            lastError: patch.lastError || null,
            processedAt: patch.processedAt || null,
          },
        });
        if (updated.count !== 1) return { applied: false };
        if (typeof patch.projectReferral === "function") await patch.projectReferral(tx);
        if (typeof patch.projectRewards === "function") await patch.projectRewards(tx);
        await tx.incentiveAuditLog.create({ data: patch.audit });
        return { applied: true };
      });
    },

    async listEligibleCampaigns(eventType, now) {
      const campaigns = await prisma.incentiveCampaign.findMany({
        where: { status: { in: ["ACTIVE", "SCHEDULED"] } },
      });
      const eligible = [];
      for (const campaign of campaigns) {
        if (!campaign.currentVersionId) continue;
        if (campaign.endsAt && new Date(campaign.endsAt) <= now) continue;
        if (campaign.status === "SCHEDULED" && (!campaign.startsAt || new Date(campaign.startsAt) > now)) continue;
        const version = await prisma.incentiveCampaignVersion.findUnique({
          where: { id: campaign.currentVersionId },
        });
        if (!version || !version.publishedAt) continue;
        const triggers = version.snapshot && Array.isArray(version.snapshot.triggers) ? version.snapshot.triggers : [];
        if (!triggers.some((trigger) => trigger && trigger.eventType === eventType)) continue;
        eligible.push({
          id: campaign.id,
          category: campaign.category,
          stackingMode: campaign.stackingMode || "STACK",
          priority: campaign.priority || 0,
          status: campaign.status,
          startsAt: campaign.startsAt,
          endsAt: campaign.endsAt,
          version: { id: version.id, snapshot: version.snapshot, publishedAt: version.publishedAt },
        });
      }
      return eligible;
    },

    async loadOrder(id) {
      const orders = prisma["order"];
      return orders.findUnique({
        where: { id },
        include: {
          items: { include: { listing: { select: { societyId: true, sellerId: true } } } },
        },
      });
    },

    async listEvents({ status, type, cursor, limit }) {
      const where = {};
      if (status) where.status = status;
      if (type) where.type = type;
      if (cursor) {
        const current = await prisma.incentiveEvent.findUnique({
          where: { id: cursor },
          select: { id: true, createdAt: true },
        });
        if (current) {
          where.AND = [
            {
              OR: [
                { createdAt: { lt: current.createdAt } },
                { createdAt: current.createdAt, id: { lt: current.id } },
              ],
            },
          ];
        }
      }
      return prisma.incentiveEvent.findMany({
        where,
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: limit,
      });
    },

    async findExpired(now, leaseMs) {
      const rows = await prisma.incentiveEvent.findMany({
        where: { status: "PROCESSING", claimToken: { not: null } },
        take: 50,
      });
      return rows.filter((row) => leaseExpired(row, now, leaseMs));
    },

    async findReconciliation(now, staleMs) {
      const [dead, failedDue, pending, processing] = await Promise.all([
        prisma.incentiveEvent.findMany({ where: { status: "DEAD" }, orderBy: { createdAt: "asc" }, take: 50 }),
        prisma.incentiveEvent.findMany({
          where: { status: "FAILED", OR: [{ nextAttemptAt: null }, { nextAttemptAt: { lte: now } }] },
          orderBy: { createdAt: "asc" },
          take: 50,
        }),
        prisma.incentiveEvent.findMany({
          where: { status: "PENDING", createdAt: { lte: new Date(now.getTime() - staleMs) } },
          orderBy: { createdAt: "asc" },
          take: 50,
        }),
        prisma.incentiveEvent.findMany({ where: { status: "PROCESSING" }, take: 50 }),
      ]);
      return {
        dead,
        failedDue,
        stalePending: pending,
        expired: processing.filter((row) => leaseExpired(row, now)),
      };
    },

    async replay(id, actorId) {
      return prisma.$transaction(async (tx) => {
        const current = await tx.incentiveEvent.findUnique({ where: { id } });
        if (!current) return { missing: true };
        if (!["FAILED", "DEAD", "SKIPPED"].includes(current.status)) return { rejected: true, event: current };
        const updated = await tx.incentiveEvent.updateMany({
          where: { id, status: current.status },
          data: {
            status: "PENDING",
            nextAttemptAt: null,
            claimToken: null,
            claimedAt: null,
            claimedBy: null,
            lastError: null,
            processedAt: null,
          },
        });
        if (updated.count !== 1) return { rejected: true, event: current };
        await tx.incentiveAuditLog.create({
          data: {
            actorId,
            action: "EVENT_REPLAY",
            incentiveEventId: id,
            before: { status: current.status, eventId: current.eventId, type: current.type },
            after: { status: "PENDING", eventId: current.eventId, type: current.type, outcome: "REPLAYED" },
          },
        });
        const event = await tx.incentiveEvent.findUnique({ where: { id } });
        return { event };
      });
    },

    isDue,
  };
}

module.exports = { conflictError, createPrismaEventRepository };
