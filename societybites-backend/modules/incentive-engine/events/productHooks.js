const logger = require("../../../lib/logger");
const { createPrismaEventRepository } = require("./repository");
const { ingestEvent } = require("./process");
const {
  isCodOutsideSellerDelivery,
  isUpiFoodCashDeliverySplit,
  qualifyOrder,
} = require("./qualifyOrder");

async function recordWithRetry(record) {
  try {
    return await record();
  } catch (first) {
    try {
      return await record();
    } catch (second) {
      second.priorMessage = first && first.message ? first.message : "unknown";
      throw second;
    }
  }
}

function afterCommit(result, record) {
  return Promise.resolve()
    .then(() => recordWithRetry(record))
    .then(() => result)
    .catch((error) => {
      logger.error("incentive", "Product event was not recorded", {
        message: error && error.message ? error.message : "unknown",
        priorMessage: error && error.priorMessage ? error.priorMessage : undefined,
      });
      return result;
    });
}

async function recordSellerBecameSeller(prisma, { userId, occurredAt }) {
  if (!userId || !occurredAt) return { recorded: false, reason: "OCCURRED_AT_UNAVAILABLE" };
  return ingestEvent(createPrismaEventRepository(prisma), {
    type: "USER_BECAME_SELLER",
    entityId: userId,
    userId,
    occurredAt,
    payload: {},
  });
}

async function recordListingPublished(prisma, listing) {
  if (!listing || !listing.id || !listing.firstPublishedAt) {
    return { recorded: false, reason: "OCCURRED_AT_UNAVAILABLE" };
  }
  return ingestEvent(createPrismaEventRepository(prisma), {
    type: "LISTING_PUBLISHED",
    entityId: listing.id,
    userId: listing.sellerId || null,
    occurredAt: listing.firstPublishedAt,
    payload: {},
  });
}

async function emitPublishedListings(prisma, listings) {
  const saved = [];
  for (const listing of listings || []) {
    saved.push(await recordListingPublished(prisma, listing));
  }
  return saved;
}

/**
 * After a listing create transaction commits. Draft rows have no
 * firstPublishedAt and are not emitted. The stored timestamp is occurredAt.
 */
function recordCreatedPublications(prisma, productResult, created) {
  const stamped = (Array.isArray(created) ? created : [created])
    .filter((row) => row && row.id && row.firstPublishedAt)
    .map((row) => ({
      id: row.id,
      sellerId: row.sellerId,
      firstPublishedAt: row.firstPublishedAt,
    }));
  if (!stamped.length) return productResult;
  return afterCommit(productResult, () => emitPublishedListings(prisma, stamped));
}

function latestDate(values) {
  const times = values
    .filter(Boolean)
    .map((value) => new Date(value))
    .filter((date) => !Number.isNaN(date.getTime()));
  if (!times.length) return null;
  return new Date(Math.max(...times.map((date) => date.getTime())));
}

/**
 * Business time for a qualified order. updatedAt, createdAt, and processedAt
 * are never read. A missing source timestamp stays missing.
 */
function qualificationOccurredAt(order) {
  if (!order || !order.completedAt) return null;
  const method = String(order.paymentMethod || "").toLowerCase();
  const provider = order.paymentProvider || null;
  if (isUpiFoodCashDeliverySplit(order)) {
    if (!order.sellerConfirmedPaidAt) return null;
    const charge = Number(order.deliveryCharge || 0);
    if (charge > 0 && !order.deliveryCashConfirmedAt) return null;
    return latestDate([
      order.completedAt,
      order.sellerConfirmedPaidAt,
      charge > 0 ? order.deliveryCashConfirmedAt : null,
    ]);
  }
  if (
    isCodOutsideSellerDelivery(order) ||
    method === "cash" ||
    provider === "cashfree" ||
    method === "upi"
  ) {
    if (!order.sellerConfirmedPaidAt) return null;
    return latestDate([order.completedAt, order.sellerConfirmedPaidAt]);
  }
  return null;
}

async function emitOrderQualifiedIfReady(prisma, orderId) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: {
      items: { include: { listing: { select: { societyId: true, sellerId: true } } } },
    },
  });
  const decision = qualifyOrder(order);
  if (!decision.qualified) return { recorded: false, reason: decision.reason };
  const occurredAt = qualificationOccurredAt(order);
  if (!occurredAt) return { recorded: false, reason: "OCCURRED_AT_UNAVAILABLE" };
  const saved = await ingestEvent(createPrismaEventRepository(prisma), {
    type: "ORDER_QUALIFIED",
    entityId: order.id,
    userId: order.buyerId || null,
    occurredAt,
    payload: {},
  });
  if (saved && saved.created) {
    logger.info("incentive", "Qualified order event recorded", {
      orderId: order.id,
      eventId: saved.event && saved.event.eventId ? saved.event.eventId : null,
    });
  }
  return saved;
}

function countSaved(report, saved) {
  if (saved && saved.created) report.inserted += 1;
  else if (saved && saved.event) report.existing += 1;
}

async function backfillProductEvents(prisma, { limit = 100 } = {}) {
  const cap = Math.min(Math.max(Number(limit) || 100, 1), 500);
  const report = {
    sellers: { inserted: 0, existing: 0, unreconstructable: [] },
    listings: { inserted: 0, existing: 0, unreconstructable: [] },
    orders: { inserted: 0, existing: 0, unreconstructable: [] },
  };

  const sellers = await prisma.user.findMany({
    where: { role: "seller" },
    select: { id: true },
    take: cap,
  });
  const acceptances = sellers.length
    ? await prisma.sellerTermsAcceptance.findMany({
        where: { userId: { in: sellers.map((row) => row.id) } },
        select: { userId: true, acceptedAt: true },
      })
    : [];
  const firstAcceptance = new Map();
  for (const row of acceptances) {
    const current = firstAcceptance.get(row.userId);
    if (!current || new Date(row.acceptedAt) < new Date(current.acceptedAt)) {
      firstAcceptance.set(row.userId, row);
    }
  }
  for (const seller of sellers) {
    const acceptance = firstAcceptance.get(seller.id);
    if (!acceptance || !acceptance.acceptedAt) {
      report.sellers.unreconstructable.push({
        userId: seller.id,
        reason: "SELLER_TERMS_ACCEPTANCE_MISSING",
      });
      continue;
    }
    countSaved(
      report.sellers,
      await recordSellerBecameSeller(prisma, {
        userId: seller.id,
        occurredAt: acceptance.acceptedAt,
      })
    );
  }

  const published = await prisma.listing.findMany({
    where: { firstPublishedAt: { not: null } },
    select: { id: true, sellerId: true, firstPublishedAt: true },
    take: cap,
  });
  for (const listing of published) {
    countSaved(report.listings, await recordListingPublished(prisma, listing));
  }
  const historical = await prisma.listing.findMany({
    where: { firstPublishedAt: null, status: { not: "draft" } },
    select: { id: true, status: true },
    take: cap,
  });
  report.listings.unreconstructable = historical.map((row) => ({
    listingId: row.id,
    status: row.status,
    reason: "FIRST_PUBLISHED_AT_UNAVAILABLE",
  }));

  const orders = await prisma.order.findMany({
    where: { status: "completed" },
    include: {
      items: { include: { listing: { select: { societyId: true, sellerId: true } } } },
    },
    take: cap,
  });
  for (const order of orders) {
    if (!qualifyOrder(order).qualified) continue;
    const occurredAt = qualificationOccurredAt(order);
    if (!occurredAt) {
      report.orders.unreconstructable.push({
        orderId: order.id,
        reason: "OCCURRED_AT_UNAVAILABLE",
      });
      continue;
    }
    countSaved(
      report.orders,
      await ingestEvent(createPrismaEventRepository(prisma), {
        type: "ORDER_QUALIFIED",
        entityId: order.id,
        userId: order.buyerId || null,
        occurredAt,
        payload: {},
      })
    );
  }
  return report;
}

module.exports = {
  afterCommit,
  backfillProductEvents,
  emitOrderQualifiedIfReady,
  emitPublishedListings,
  recordCreatedPublications,
  qualificationOccurredAt,
  recordListingPublished,
  recordSellerBecameSeller,
};
