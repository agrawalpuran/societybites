const crypto = require("crypto");
const prisma = require("./prisma");
const { parseFssaiNumber } = require("./fssai");
const { uploadPrivateObject, createSignedObjectUrl } = require("./objectStorage");
const { parseImageUpload } = require("./profileImage");
const { isFssaiSellingRequirementEnabled } = require("./fssaiRequirement");

const FSSAI_STATUSES = ["NOT_SUBMITTED", "UNDER_REVIEW", "APPROVED", "REJECTED"];
const ASSISTANCE_STATUSES = ["NEW", "CONTACTED", "IN_PROGRESS", "COMPLETED"];
const REJECTION_PRESETS = [
  "Document unclear",
  "Registration number does not match",
  "Document appears invalid",
  "Wrong document",
  "Other",
];

function httpError(statusCode, message, extra) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (extra && typeof extra === "object") Object.assign(err, extra);
  return err;
}

function isSellerRole(role) {
  return role === "seller" || role === "super_admin";
}

function serializeSellerFssai(row) {
  if (!row) {
    return {
      status: "NOT_SUBMITTED",
      registrationNumber: null,
      rejectionReason: null,
      submittedAt: null,
      reviewedAt: null,
      needsAssistance: false,
      hasDocument: false,
    };
  }
  return {
    status: row.status || "NOT_SUBMITTED",
    registrationNumber: row.registrationNumber || null,
    rejectionReason: row.rejectionReason || null,
    submittedAt: row.submittedAt || null,
    reviewedAt: row.reviewedAt || null,
    needsAssistance: Boolean(row.needsAssistance),
    hasDocument: Boolean(row.documentStorageReference),
  };
}

async function ensureSellerFssaiRow(userId) {
  const existing = await prisma.sellerFssai.findUnique({ where: { userId } });
  if (existing) return existing;
  return prisma.sellerFssai.create({
    data: { id: crypto.randomUUID(), userId, status: "NOT_SUBMITTED" },
  });
}

async function getSellerFssaiStatus(userId) {
  const row = await prisma.sellerFssai.findUnique({ where: { userId } });
  return row ? row.status : "NOT_SUBMITTED";
}

async function sellerCanReceiveOrders(userId) {
  const requirement = await isFssaiSellingRequirementEnabled();
  if (!requirement) return true;
  const status = await getSellerFssaiStatus(userId);
  return status === "APPROVED";
}

async function assertSellerCanReceiveOrders(userId) {
  const ok = await sellerCanReceiveOrders(userId);
  if (ok) return;
  throw httpError(
    400,
    "This seller cannot receive new orders until FSSAI registration is approved",
    { code: "FSSAI_REQUIRED" }
  );
}

async function getMyFssai(user) {
  if (!isSellerRole(user.role)) {
    throw httpError(400, "Only sellers can view FSSAI registration");
  }
  const row = await ensureSellerFssaiRow(user.id);
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  const assistance = await prisma.fssaiAssistanceRequest.findFirst({
    where: {
      userId: user.id,
      status: { in: ["NEW", "CONTACTED", "IN_PROGRESS"] },
    },
    orderBy: { requestedAt: "desc" },
  });
  return {
    ...serializeSellerFssai(row),
    requirementEnabled,
    assistanceRequested: Boolean(assistance),
    assistanceStatus: assistance ? assistance.status : null,
    canSellDespiteFssai: !requirementEnabled || row.status === "APPROVED",
  };
}

async function uploadMyFssaiDocument(user, body) {
  if (!isSellerRole(user.role)) {
    throw httpError(400, "Only sellers can upload FSSAI documents");
  }
  const parsed = parseImageUpload(body);
  const storageReference = await uploadPrivateObject({
    buffer: parsed.buffer,
    mimeType: parsed.mimeType,
    userId: user.id,
    prefix: "fssai-private",
  });
  const row = await ensureSellerFssaiRow(user.id);
  await prisma.sellerFssai.update({
    where: { id: row.id },
    data: {
      documentStorageReference: storageReference,
      documentType: parsed.mimeType,
    },
  });
  return { storageReference };
}

async function submitMyFssai(user, body) {
  if (!isSellerRole(user.role)) {
    throw httpError(400, "Only sellers can submit FSSAI registration");
  }
  const source = body && typeof body === "object" ? body : {};
  const registrationNumber = parseFssaiNumber(source.registrationNumber);
  if (!registrationNumber) {
    throw httpError(400, "FSSAI registration number is required");
  }
  let storageReference =
    source.storageReference != null ? String(source.storageReference).trim() : "";
  if (!storageReference && source.documentStorageReference != null) {
    storageReference = String(source.documentStorageReference).trim();
  }
  const row = await ensureSellerFssaiRow(user.id);
  if (!storageReference && !row.documentStorageReference) {
    throw httpError(400, "FSSAI document is required");
  }
  if (storageReference && !storageReference.startsWith("fssai-private/")) {
    throw httpError(400, "Invalid document reference");
  }
  const effectiveRef = storageReference || row.documentStorageReference;
  const updated = await prisma.sellerFssai.update({
    where: { id: row.id },
    data: {
      registrationNumber,
      documentStorageReference: effectiveRef,
      status: "UNDER_REVIEW",
      rejectionReason: null,
      submittedAt: new Date(),
      reviewedAt: null,
      reviewedBy: null,
    },
  });
  return serializeSellerFssai(updated);
}

async function getMyFssaiDocumentUrl(user) {
  const row = await prisma.sellerFssai.findUnique({ where: { userId: user.id } });
  if (!row || !row.documentStorageReference) {
    throw httpError(404, "Document not found");
  }
  const url = await createSignedObjectUrl(row.documentStorageReference, 300);
  return { url, expiresInSeconds: 300 };
}

async function requestFssaiAssistance(user) {
  if (!isSellerRole(user.role)) {
    throw httpError(400, "Only sellers can request FSSAI assistance");
  }
  await prisma.sellerFssai.updateMany({
    where: { userId: user.id },
    data: { needsAssistance: true },
  });
  const existing = await prisma.fssaiAssistanceRequest.findFirst({
    where: {
      userId: user.id,
      status: { in: ["NEW", "CONTACTED", "IN_PROGRESS"] },
    },
  });
  if (existing) return existing;
  return prisma.fssaiAssistanceRequest.create({
    data: {
      id: crypto.randomUUID(),
      userId: user.id,
      societyId: user.societyId || null,
      status: "NEW",
    },
  });
}

async function getAdminFssaiSummary() {
  const [requirementEnabled, grouped, assistanceGrouped] = await Promise.all([
    isFssaiSellingRequirementEnabled(),
    prisma.sellerFssai.groupBy({
      by: ["status"],
      _count: { _all: true },
    }),
    prisma.fssaiAssistanceRequest.groupBy({
      by: ["status"],
      _count: { _all: true },
    }),
  ]);
  const counts = Object.fromEntries(FSSAI_STATUSES.map((s) => [s, 0]));
  for (const row of grouped) {
    counts[row.status] = row._count._all;
  }
  const assistance = { NEW: 0, CONTACTED: 0, IN_PROGRESS: 0, COMPLETED: 0 };
  for (const row of assistanceGrouped) {
    assistance[row.status] = row._count._all;
  }
  return {
    requirementEnabled,
    submissions: counts,
    assistance,
    pendingReview: counts.UNDER_REVIEW || 0,
  };
}

async function listAdminFssaiSubmissions({ status } = {}) {
  const where = {};
  if (status && status !== "ALL") {
    const normalized = String(status).trim().toUpperCase();
    if (!FSSAI_STATUSES.includes(normalized)) {
      throw httpError(400, "Invalid status filter");
    }
    where.status = normalized;
  }
  const rows = await prisma.sellerFssai.findMany({
    where,
    include: {
      user: {
        select: {
          id: true,
          name: true,
          phone: true,
          society: { select: { name: true } },
        },
      },
    },
    orderBy: [{ status: "asc" }, { submittedAt: "desc" }],
  });
  return rows.map((row) => ({
    sellerId: row.userId,
    name: row.user?.name || "Seller",
    phone: row.user?.phone || null,
    societyName: row.user?.society?.name || null,
    registrationNumber: row.registrationNumber,
    status: row.status,
    submittedAt: row.submittedAt,
    reviewedAt: row.reviewedAt,
    rejectionReason: row.rejectionReason,
    hasDocument: Boolean(row.documentStorageReference),
    needsAssistance: row.needsAssistance,
  }));
}

async function getAdminFssaiDocumentUrl(adminUser, sellerId) {
  const row = await prisma.sellerFssai.findUnique({
    where: { userId: String(sellerId) },
  });
  if (!row || !row.documentStorageReference) {
    throw httpError(404, "Document not found");
  }
  const url = await createSignedObjectUrl(row.documentStorageReference, 300);
  return { url, expiresInSeconds: 300 };
}

async function approveAdminFssai(adminUser, sellerId) {
  const row = await prisma.sellerFssai.findUnique({ where: { userId: String(sellerId) } });
  if (!row) throw httpError(404, "FSSAI submission not found");
  if (row.status !== "UNDER_REVIEW") {
    throw httpError(400, "Only submissions under review can be approved");
  }
  const updated = await prisma.sellerFssai.update({
    where: { id: row.id },
    data: {
      status: "APPROVED",
      rejectionReason: null,
      reviewedAt: new Date(),
      reviewedBy: adminUser.id,
    },
  });
  return serializeSellerFssai(updated);
}

async function rejectAdminFssai(adminUser, sellerId, body) {
  const reason = body && body.rejectionReason != null ? String(body.rejectionReason).trim() : "";
  if (!reason) throw httpError(400, "Rejection reason is required");
  if (reason.length > 500) throw httpError(400, "Rejection reason is too long");
  const row = await prisma.sellerFssai.findUnique({ where: { userId: String(sellerId) } });
  if (!row) throw httpError(404, "FSSAI submission not found");
  if (row.status !== "UNDER_REVIEW") {
    throw httpError(400, "Only submissions under review can be rejected");
  }
  const updated = await prisma.sellerFssai.update({
    where: { id: row.id },
    data: {
      status: "REJECTED",
      rejectionReason: reason,
      reviewedAt: new Date(),
      reviewedBy: adminUser.id,
    },
  });
  return serializeSellerFssai(updated);
}

async function listAdminFssaiAssistance({ status } = {}) {
  const where = {};
  if (status && status !== "ALL") {
    const normalized = String(status).trim().toUpperCase();
    if (!ASSISTANCE_STATUSES.includes(normalized)) {
      throw httpError(400, "Invalid assistance status");
    }
    where.status = normalized;
  }
  const rows = await prisma.fssaiAssistanceRequest.findMany({
    where,
    include: {
      user: { select: { id: true, name: true, phone: true } },
      society: { select: { name: true } },
    },
    orderBy: { requestedAt: "desc" },
  });
  return rows.map((row) => ({
    id: row.id,
    sellerId: row.userId,
    sellerName: row.user?.name || "Seller",
    phone: row.user?.phone || null,
    societyName: row.society?.name || null,
    status: row.status,
    requestedAt: row.requestedAt,
  }));
}

async function updateAdminFssaiAssistance(id, body) {
  const status = body && body.status != null ? String(body.status).trim().toUpperCase() : "";
  if (!ASSISTANCE_STATUSES.includes(status)) {
    throw httpError(400, "Invalid assistance status");
  }
  const row = await prisma.fssaiAssistanceRequest.findUnique({ where: { id: String(id) } });
  if (!row) throw httpError(404, "Assistance request not found");
  return prisma.fssaiAssistanceRequest.update({
    where: { id: row.id },
    data: { status },
  });
}

async function statusesForSellerIds(sellerIds) {
  const ids = [...new Set((sellerIds || []).filter(Boolean))];
  if (!ids.length) return {};
  const rows = await prisma.sellerFssai.findMany({
    where: { userId: { in: ids } },
    select: { userId: true, status: true },
  });
  const map = {};
  for (const id of ids) map[id] = "NOT_SUBMITTED";
  for (const row of rows) map[row.userId] = row.status;
  return map;
}

module.exports = {
  FSSAI_STATUSES,
  ASSISTANCE_STATUSES,
  REJECTION_PRESETS,
  serializeSellerFssai,
  ensureSellerFssaiRow,
  getSellerFssaiStatus,
  sellerCanReceiveOrders,
  assertSellerCanReceiveOrders,
  getMyFssai,
  uploadMyFssaiDocument,
  submitMyFssai,
  getMyFssaiDocumentUrl,
  requestFssaiAssistance,
  getAdminFssaiSummary,
  listAdminFssaiSubmissions,
  getAdminFssaiDocumentUrl,
  approveAdminFssai,
  rejectAdminFssai,
  listAdminFssaiAssistance,
  updateAdminFssaiAssistance,
  statusesForSellerIds,
};
