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

function optionalImageUrl(value) {
  if (value == null || String(value).trim() === "") return null;
  const text = String(value).trim();
  if (text.length > 500 || !/^https:\/\//i.test(text)) {
    throw httpError(400, "Photo is invalid");
  }
  return text;
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
    imageUrl: optionalImageUrl(source.imageUrl),
    userId: user.id,
    userRole: role,
  };
}

function issueReference(issueNumber) {
  return `SE-${issueNumber}`;
}

function serializeMessage(row) {
  return {
    id: row.id,
    authorRole: row.authorRole,
    body: row.body,
    imageUrl: row.imageUrl,
    createdAt: row.createdAt,
  };
}

function threadFor(row) {
  const stored = Array.isArray(row.messages) ? row.messages : [];
  if (stored.length) return stored.map(serializeMessage);
  const thread = [
    {
      id: `${row.id}-opened`,
      authorRole: "USER",
      body: row.description,
      imageUrl: row.imageUrl || null,
      createdAt: row.createdAt,
    },
  ];
  if (row.adminResponse) {
    thread.push({
      id: `${row.id}-admin`,
      authorRole: "SOCIETYEATS",
      body: row.adminResponse,
      imageUrl: null,
      createdAt: row.adminRespondedAt || row.updatedAt,
    });
  }
  return thread;
}

function serializeIssue(row, { includeReporter = false, includeThread = false } = {}) {
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
    adminRespondedAt: row.adminRespondedAt || null,
    imageUrl: row.imageUrl || null,
    platform: row.platform,
    appVersion: row.appVersion,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    resolvedAt: row.resolvedAt,
  };
  if (includeThread) payload.messages = threadFor(row);
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
  let row;
  try {
    row = await prisma.issueReport.create({
      data: {
        id,
        reference: `pending-${id}`,
        ...input,
      },
    });
    // Batch transaction (not interactive) — works with Supabase PgBouncer pooler.
    await prisma.$transaction([
      prisma.issueMessage.create({
        data: {
          issueId: row.id,
          authorId: input.userId,
          authorRole: "USER",
          body: input.description,
          imageUrl: input.imageUrl,
        },
      }),
      prisma.issueReport.update({
        where: { id: row.id },
        data: { reference: issueReference(row.issueNumber) },
      }),
    ]);
  } catch (err) {
    if (row) {
      await prisma.issueReport.delete({ where: { id: row.id } }).catch(() => {});
    }
    throw err;
  }
  const created = await prisma.issueReport.findUnique({
    where: { id: row.id },
    include: { messages: { orderBy: { createdAt: "asc" } } },
  });
  return serializeIssue(created, { includeThread: true });
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
    include: { messages: { orderBy: { createdAt: "asc" } } },
  });
  if (!row) throw httpError(404, "Report not found");
  return serializeIssue(row, { includeThread: true });
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
    include: {
      user: { select: { name: true } },
      messages: { orderBy: { createdAt: "asc" } },
    },
  });
  if (!row) throw httpError(404, "Report not found");
  return serializeIssue(row, { includeReporter: true, includeThread: true });
}

async function backfillThread(issue) {
  const count = await prisma.issueMessage.count({ where: { issueId: issue.id } });
  if (count > 0) return;
  const ops = [
    prisma.issueMessage.create({
      data: {
        issueId: issue.id,
        authorId: issue.userId,
        authorRole: "USER",
        body: issue.description,
        imageUrl: issue.imageUrl,
        createdAt: issue.createdAt,
      },
    }),
  ];
  if (issue.adminResponse) {
    ops.push(
      prisma.issueMessage.create({
        data: {
          issueId: issue.id,
          authorId: issue.userId,
          authorRole: "SOCIETYEATS",
          body: issue.adminResponse,
          createdAt: issue.adminRespondedAt || issue.updatedAt,
        },
      })
    );
  }
  await prisma.$transaction(ops);
}

async function addUserReply(user, issueId, body) {
  const source = body && typeof body === "object" ? body : {};
  const text = String(source.body || "").trim();
  const imageUrl = optionalImageUrl(source.imageUrl);
  if (!text && !imageUrl) throw httpError(400, "Write a reply or add a photo");
  if (text.length > MAX_TEXT) {
    throw httpError(400, `Reply must be ${MAX_TEXT} characters or less`);
  }
  const issue = await prisma.issueReport.findFirst({
    where: { id: issueId, userId: user.id },
  });
  if (!issue) throw httpError(404, "Report not found");
  await backfillThread(issue);
  await prisma.issueMessage.create({
    data: {
      issueId,
      authorId: user.id,
      authorRole: "USER",
      body: text,
      imageUrl,
    },
  });
  return getOwnIssue(user.id, issueId);
}

async function updateAdminIssue(id, body, adminUser) {
  const source = body && typeof body === "object" ? body : {};
  const existing = await prisma.issueReport.findUnique({
    where: { id },
    include: { messages: { orderBy: { createdAt: "asc" } } },
  });
  if (!existing) throw httpError(404, "Report not found");
  const data = {};
  if (source.status != null) {
    const status = String(source.status).trim().toUpperCase();
    if (!ISSUE_STATUSES.includes(status)) {
      throw httpError(400, "Status is invalid");
    }
    data.status = status;
    data.resolvedAt = status === "RESOLVED" || status === "CLOSED" ? new Date() : null;
  }
  let reply = null;
  if (Object.prototype.hasOwnProperty.call(source, "adminResponse")) {
    const text = source.adminResponse == null ? "" : String(source.adminResponse).trim();
    if (text.length > MAX_TEXT) {
      throw httpError(400, `Response must be ${MAX_TEXT} characters or less`);
    }
    data.adminResponse = text || null;
    if (text) {
      const previous = (existing.messages || []).filter((row) => row.authorRole === "SOCIETYEATS");
      const last = previous[previous.length - 1];
      const alreadyStored = !last && text === (existing.adminResponse || "");
      if (!alreadyStored && (!last || last.body !== text)) reply = text;
    }
  }
  if (!Object.keys(data).length) {
    throw httpError(400, "Nothing to update");
  }
  await backfillThread(existing);
  if (reply) {
    data.adminRespondedAt = new Date();
    await prisma.issueMessage.create({
      data: {
        issueId: id,
        authorId: adminUser.id,
        authorRole: "SOCIETYEATS",
        body: reply,
      },
    });
  }
  const row = await prisma.issueReport.update({
    where: { id },
    data,
    include: {
      user: { select: { name: true } },
      messages: { orderBy: { createdAt: "asc" } },
    },
  });
  return serializeIssue(row, { includeReporter: true, includeThread: true });
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
  addUserReply,
};
