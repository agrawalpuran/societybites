const crypto = require("crypto");
const prisma = require("./prisma");

const ISSUE_CATEGORIES = [
  "ORDER_ISSUE",
  "PAYMENT_UPI",
  "FOOD_LISTING",
  "SELLER",
  "BUYER",
  "APP_ISSUE",
  "OTHER",
];

const ISSUE_STATUSES = ["OPEN", "UNDER_REVIEW", "RESOLVED", "CLOSED"];
const ISSUE_PLATFORMS = ["ANDROID", "IOS", "WEB"];
const MAX_TEXT = 2000;
const STATUS_RANK = {
  OPEN: 0,
  UNDER_REVIEW: 1,
  RESOLVED: 2,
  CLOSED: 3,
};

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function optionalId(value, label) {
  if (value == null || value === "") return null;
  const text = String(value).trim();
  if (!text || text.length > 80) {
    throw httpError(400, `${label} is invalid`);
  }
  return text;
}

function assertIssueCreate(body, user) {
  if (!user || !user.id) throw httpError(401, "Not authenticated");
  const source = body && typeof body === "object" ? body : {};
  const category = String(source.category || "").trim();
  const description = String(source.description || "").trim();
  if (!ISSUE_CATEGORIES.includes(category)) {
    throw httpError(400, "Choose a category");
  }
  if (!description) {
    throw httpError(400, "Tell us what happened");
  }
  if (description.length > MAX_TEXT) {
    throw httpError(400, `Description must be ${MAX_TEXT} characters or less`);
  }

  let platform = null;
  if (source.platform != null && String(source.platform).trim() !== "") {
    platform = String(source.platform).trim().toUpperCase();
    if (!ISSUE_PLATFORMS.includes(platform)) {
      throw httpError(400, "Platform is invalid");
    }
  }

  let appVersion = null;
  if (source.appVersion != null && String(source.appVersion).trim() !== "") {
    appVersion = String(source.appVersion).trim();
    if (appVersion.length > 40) {
      throw httpError(400, "App version is invalid");
    }
  }

  const role = user.role === "seller" || user.role === "super_admin" ? user.role : "buyer";
  return {
    category,
    description,
    orderId: optionalId(source.orderId, "Order"),
    listingId: optionalId(source.listingId, "Listing"),
    sellerId: optionalId(source.sellerId, "Seller"),
    platform,
    appVersion,
    userId: user.id,
    userRole: role,
  };
}

function issueReference(issueNumber) {
  return `SE-${issueNumber}`;
}

function serializeIssue(row, { includeReporter = false } = {}) {
  const payload = {
    id: row.id,
    reference: row.reference,
    userId: row.userId,
    userRole: row.userRole,
    category: row.category,
    description: row.description,
    orderId: row.orderId,
    listingId: row.listingId,
    sellerId: row.sellerId,
    status: row.status,
    adminResponse: row.adminResponse,
    platform: row.platform,
    appVersion: row.appVersion,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    resolvedAt: row.resolvedAt,
  };
  if (includeReporter) {
    payload.reporter = {
      name: row.user && row.user.name ? row.user.name : "Resident",
      role: row.userRole,
    };
  }
  return payload;
}

function sortIssues(rows) {
  return [...rows].sort((a, b) => {
    const rank = (STATUS_RANK[a.status] ?? 9) - (STATUS_RANK[b.status] ?? 9);
    if (rank !== 0) return rank;
    return new Date(b.createdAt) - new Date(a.createdAt);
  });
}

async function createIssueReport(body, user) {
  const input = assertIssueCreate(body, user);
  const id = crypto.randomUUID();
  const created = await prisma.$transaction(async (tx) => {
    const row = await tx.issueReport.create({
      data: {
        id,
        reference: `pending-${id}`,
        ...input,
      },
    });
    return tx.issueReport.update({
      where: { id: row.id },
      data: { reference: issueReference(row.issueNumber) },
    });
  });
  return serializeIssue(created);
}

async function listMyIssues(userId) {
  const rows = await prisma.issueReport.findMany({
    where: { userId },
    orderBy: { createdAt: "desc" },
  });
  return rows.map((row) => serializeIssue(row));
}

async function getOwnIssue(userId, id) {
  const row = await prisma.issueReport.findFirst({
    where: { id, userId },
  });
  if (!row) throw httpError(404, "Report not found");
  return serializeIssue(row);
}

async function listAdminIssues(status) {
  const where = {};
  if (status && status !== "ALL") {
    const normalized = String(status).trim().toUpperCase();
    if (!ISSUE_STATUSES.includes(normalized)) {
      throw httpError(400, "Status is invalid");
    }
    where.status = normalized;
  }
  const rows = await prisma.issueReport.findMany({
    where,
    include: { user: { select: { name: true } } },
    orderBy: { createdAt: "desc" },
  });
  return sortIssues(rows).map((row) => serializeIssue(row, { includeReporter: true }));
}

async function getAdminIssue(id) {
  const row = await prisma.issueReport.findUnique({
    where: { id },
    include: { user: { select: { name: true } } },
  });
  if (!row) throw httpError(404, "Report not found");
  return serializeIssue(row, { includeReporter: true });
}

async function updateAdminIssue(id, body) {
  const source = body && typeof body === "object" ? body : {};
  const data = {};
  if (source.status != null) {
    const status = String(source.status).trim().toUpperCase();
    if (!ISSUE_STATUSES.includes(status)) {
      throw httpError(400, "Status is invalid");
    }
    data.status = status;
    data.resolvedAt = status === "RESOLVED" || status === "CLOSED" ? new Date() : null;
  }
  if (Object.prototype.hasOwnProperty.call(source, "adminResponse")) {
    const text = source.adminResponse == null ? "" : String(source.adminResponse).trim();
    if (text.length > MAX_TEXT) {
      throw httpError(400, `Response must be ${MAX_TEXT} characters or less`);
    }
    data.adminResponse = text || null;
  }
  if (!Object.keys(data).length) {
    throw httpError(400, "Nothing to update");
  }
  try {
    const row = await prisma.issueReport.update({
      where: { id },
      data,
      include: { user: { select: { name: true } } },
    });
    return serializeIssue(row, { includeReporter: true });
  } catch (err) {
    if (err.code === "P2025") throw httpError(404, "Report not found");
    throw err;
  }
}

module.exports = {
  ISSUE_CATEGORIES,
  ISSUE_STATUSES,
  MAX_TEXT,
  assertIssueCreate,
  issueReference,
  sortIssues,
  serializeIssue,
  createIssueReport,
  listMyIssues,
  getOwnIssue,
  listAdminIssues,
  getAdminIssue,
  updateAdminIssue,
};
