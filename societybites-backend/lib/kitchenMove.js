const prisma = require("./prisma");
const { isAnonymizedDeletedUser } = require("./accountDeletion");
const { resolveOptionalFlat, resolveSociety } = require("./buyerAddresses");
const { isFssaiSellingRequirementEnabled } = require("./fssaiRequirement");
const {
  parseFssaiExpiry,
  parseFssaiNumber,
  parseFssaiRegisteredName,
} = require("./fssai");
const { parseImageUpload } = require("./profileImage");
const { createSignedObjectUrl, uploadPrivateObject } = require("./objectStorage");

const MOVE_STATUSES = ["PENDING", "APPROVED", "REJECTED", "CANCELLED"];
const PROOF_STATUSES = ["PENDING", "OK", "FOLLOW_UP"];

const moveInclude = {
  user: {
    select: { id: true, name: true, phone: true, role: true, societyId: true, flatId: true },
  },
  fromSociety: { select: { id: true, name: true, city: true } },
  toSociety: { select: { id: true, name: true, city: true } },
  toFlat: { select: { id: true, block: true, flatNumber: true } },
};

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function assertSeller(user) {
  if (!user) throw httpError(401, "Sign in to move your kitchen");
  if (user.role !== "seller" && user.role !== "super_admin") {
    throw httpError(403, "Kitchen moves are for sellers");
  }
  if (!user.societyId) {
    throw httpError(400, "Join your society before moving the kitchen");
  }
}

function assertAddressProofUrl(value) {
  const text = String(value || "").trim();
  if (!text) throw httpError(400, "Address proof is required");
  if (text.length > 2000 || !/^https:\/\//i.test(text)) {
    throw httpError(400, "Address proof is invalid");
  }
  return text;
}

async function withFssaiPhoto(move, row) {
  if (!move || !row || !row.fssaiDocumentStorageReference) return move;
  try {
    move.fssaiDocumentUrl = await createSignedObjectUrl(
      row.fssaiDocumentStorageReference,
      300
    );
  } catch (_) {
    move.fssaiDocumentUrl = null;
  }
  return move;
}

function serializeMove(row, requirementEnabled) {
  if (!row) return null;
  const fssaiAttached = Boolean(
    row.fssaiRegistrationNumber && row.fssaiDocumentStorageReference
  );
  const blockedByFssai =
    requirementEnabled === true && row.fssaiStatus !== "APPROVED";
  return {
    id: row.id,
    userId: row.userId,
    sellerName: row.user?.name || "Seller",
    phone: row.user?.phone || null,
    status: row.status,
    fromSocietyId: row.fromSocietyId,
    fromSocietyName: row.fromSociety?.name || null,
    fromSocietyCity: row.fromSociety?.city || null,
    toSocietyId: row.toSocietyId,
    toSocietyName: row.toSociety?.name || null,
    toSocietyCity: row.toSociety?.city || null,
    toBlock: row.toBlock || row.toFlat?.block || null,
    toFlatNumber: row.toFlatNumber || row.toFlat?.flatNumber || null,
    addressProofUrl: row.addressProofUrl,
    addressProofStatus: row.addressProofStatus || "PENDING",
    fssaiStatus: row.fssaiStatus || "NOT_SUBMITTED",
    fssaiRegistrationNumber: row.fssaiRegistrationNumber,
    fssaiRegisteredName: row.fssaiRegisteredName,
    fssaiLicenceExpiry: row.fssaiLicenceExpiry,
    fssaiAttached,
    fssaiRejectionReason: row.fssaiRejectionReason,
    fssaiSellingRequirement: requirementEnabled === true,
    canApproveMove: row.status === "PENDING" && !blockedByFssai,
    approveBlockReason: blockedByFssai
      ? "Approve the FSSAI for the new society before moving this kitchen"
      : null,
    rejectionReason: row.rejectionReason,
    createdAt: row.createdAt,
    reviewedAt: row.reviewedAt,
  };
}

async function loadMove(id) {
  return prisma.kitchenMove.findUnique({
    where: { id: String(id) },
    include: moveInclude,
  });
}

async function pendingMove(userId) {
  return prisma.kitchenMove.findFirst({
    where: { userId, status: "PENDING" },
    include: moveInclude,
    orderBy: { createdAt: "desc" },
  });
}

function assertPending(row) {
  if (!row || isAnonymizedDeletedUser(row.user)) {
    throw httpError(404, "Kitchen move not found");
  }
  if (row.status !== "PENDING") {
    throw httpError(400, "This kitchen move is already finished");
  }
}

async function optionalFssai(user, body) {
  if (!body || body.fssai == null) return null;
  const source = body.fssai;
  if (typeof source !== "object" || Array.isArray(source)) {
    throw httpError(400, "FSSAI details are invalid");
  }
  const registrationNumber = parseFssaiNumber(source.registrationNumber);
  if (!registrationNumber) {
    throw httpError(400, "FSSAI registration number is required");
  }
  const registeredName = parseFssaiRegisteredName(source.registeredName);
  if (!registeredName) throw httpError(400, "FSSAI registered name is required");
  const licenceExpiry = parseFssaiExpiry(
    source.licenceExpiry !== undefined ? source.licenceExpiry : source.expiry
  );
  if (!licenceExpiry) throw httpError(400, "FSSAI licence expiry is required");
  const parsed = parseImageUpload(source);
  const storageReference = await uploadPrivateObject({
    buffer: parsed.buffer,
    mimeType: parsed.mimeType,
    userId: user.id,
    prefix: "fssai-private",
  });
  return {
    fssaiRegistrationNumber: registrationNumber,
    fssaiRegisteredName: registeredName,
    fssaiLicenceExpiry: licenceExpiry,
    fssaiDocumentStorageReference: storageReference,
    fssaiDocumentType: parsed.mimeType,
    fssaiStatus: "NOT_SUBMITTED",
    fssaiRejectionReason: null,
    fssaiReviewedAt: null,
    fssaiReviewedBy: null,
  };
}

async function getMyKitchenMove(user) {
  assertSeller(user);
  const [move, requirementEnabled, society, flat] = await Promise.all([
    pendingMove(user.id),
    isFssaiSellingRequirementEnabled(),
    prisma.society.findUnique({
      where: { id: user.societyId },
      select: { id: true, name: true, city: true },
    }),
    user.flatId
      ? prisma.flat.findUnique({
          where: { id: user.flatId },
          select: { block: true, flatNumber: true },
        })
      : null,
  ]);
  return {
    currentSociety: society,
    currentFlat: flat,
    fssaiSellingRequirement: requirementEnabled,
    move: serializeMove(move, requirementEnabled),
  };
}

async function submitKitchenMove(user, body) {
  assertSeller(user);
  const source = body && typeof body === "object" ? body : {};
  const proofUrl = assertAddressProofUrl(source.addressProofUrl);
  const society = await resolveSociety(source);
  if (society.id === user.societyId) {
    throw httpError(400, "Choose a different society");
  }
  const flat = await resolveOptionalFlat(society.id, source);
  const fssai = await optionalFssai(user, source);
  const data = {
    fromSocietyId: user.societyId,
    fromFlatId: user.flatId,
    toSocietyId: society.id,
    toFlatId: flat ? flat.id : null,
    toBlock: flat ? flat.block : null,
    toFlatNumber: flat ? flat.flatNumber : null,
    addressProofUrl: proofUrl,
    addressProofStatus: "PENDING",
    addressProofReviewedAt: null,
    addressProofReviewedBy: null,
    fssaiRegistrationNumber: null,
    fssaiRegisteredName: null,
    fssaiLicenceExpiry: null,
    fssaiDocumentStorageReference: null,
    fssaiDocumentType: null,
    fssaiStatus: "NOT_SUBMITTED",
    fssaiRejectionReason: null,
    fssaiReviewedAt: null,
    fssaiReviewedBy: null,
    ...(fssai || {}),
  };
  const existing = await pendingMove(user.id);
  const saved = existing
    ? await prisma.kitchenMove.update({
        where: { id: existing.id },
        data,
        include: moveInclude,
      })
    : await prisma.kitchenMove.create({
        data: { userId: user.id, status: "PENDING", ...data },
        include: moveInclude,
      });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function cancelMyKitchenMove(user) {
  assertSeller(user);
  const existing = await pendingMove(user.id);
  if (!existing) throw httpError(404, "No kitchen move is waiting");
  const saved = await prisma.kitchenMove.update({
    where: { id: existing.id },
    data: { status: "CANCELLED" },
    include: moveInclude,
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function listKitchenMoves({ status } = {}) {
  const requested = String(status || "PENDING").trim().toUpperCase();
  const where = {};
  if (requested !== "ALL") {
    if (!MOVE_STATUSES.includes(requested)) {
      throw httpError(400, "Invalid kitchen move status");
    }
    where.status = requested;
  }
  const rows = await prisma.kitchenMove.findMany({
    where,
    include: moveInclude,
    orderBy: { createdAt: "desc" },
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return rows
    .filter((row) => !isAnonymizedDeletedUser(row.user))
    .map((row) => serializeMove(row, requirementEnabled));
}

async function getKitchenMove(id) {
  const row = await loadMove(id);
  if (!row || isAnonymizedDeletedUser(row.user)) {
    throw httpError(404, "Kitchen move not found");
  }
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(row, requirementEnabled), row);
}

async function reviewMoveAddressProof({ adminUser, id, status }) {
  const next = String(status || "").trim().toUpperCase();
  if (!PROOF_STATUSES.includes(next) || next === "PENDING") {
    throw httpError(400, "Invalid address proof status");
  }
  const row = await loadMove(id);
  assertPending(row);
  const saved = await prisma.kitchenMove.update({
    where: { id: row.id },
    data: {
      addressProofStatus: next,
      addressProofReviewedAt: new Date(),
      addressProofReviewedBy: adminUser.id,
    },
    include: moveInclude,
  });
  await prisma.auditLog.create({
    data: {
      adminId: adminUser.id,
      action: "KITCHEN_MOVE_PROOF",
      target: row.id,
      details: JSON.stringify({ from: row.addressProofStatus, to: next }),
    },
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function sendMoveFssaiToReview({ adminUser, id }) {
  const row = await loadMove(id);
  assertPending(row);
  if (!row.fssaiRegistrationNumber || !row.fssaiDocumentStorageReference) {
    throw httpError(400, "This move has no FSSAI to review");
  }
  if (row.fssaiStatus === "UNDER_REVIEW" || row.fssaiStatus === "APPROVED") {
    throw httpError(400, "This FSSAI is already in review");
  }
  const saved = await prisma.kitchenMove.update({
    where: { id: row.id },
    data: {
      fssaiStatus: "UNDER_REVIEW",
      fssaiRejectionReason: null,
    },
    include: moveInclude,
  });
  await prisma.auditLog.create({
    data: {
      adminId: adminUser.id,
      action: "KITCHEN_MOVE_FSSAI_REVIEW",
      target: row.id,
      details: JSON.stringify({
        addressProofStatus: row.addressProofStatus,
        to: "UNDER_REVIEW",
      }),
    },
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function copyApprovedLicence(tx, row, adminUser) {
  const data = {
    registrationNumber: row.fssaiRegistrationNumber,
    registeredName: row.fssaiRegisteredName,
    licenceExpiry: row.fssaiLicenceExpiry,
    documentStorageReference: row.fssaiDocumentStorageReference,
    documentType: row.fssaiDocumentType,
    status: "APPROVED",
    rejectionReason: null,
    submittedAt: new Date(),
    reviewedAt: new Date(),
    reviewedBy: adminUser.id,
    needsAssistance: false,
    detailsDeferred: false,
  };
  await tx.sellerFssai.upsert({
    where: { userId: row.userId },
    create: { userId: row.userId, ...data },
    update: data,
  });
  await tx.user.update({
    where: { id: row.userId },
    data: {
      fssaiNumber: row.fssaiRegistrationNumber,
      fssaiRegisteredName: row.fssaiRegisteredName,
      fssaiExpiry: row.fssaiLicenceExpiry,
    },
  });
}

async function approveMoveFssai({ adminUser, id }) {
  const row = await loadMove(id);
  if (!row || isAnonymizedDeletedUser(row.user)) {
    throw httpError(404, "Kitchen move not found");
  }
  if (row.fssaiStatus !== "UNDER_REVIEW") {
    throw httpError(400, "Only an FSSAI that needs review can be approved");
  }
  const saved = await prisma.$transaction(async (tx) => {
    const updated = await tx.kitchenMove.update({
      where: { id: row.id },
      data: {
        fssaiStatus: "APPROVED",
        fssaiRejectionReason: null,
        fssaiReviewedAt: new Date(),
        fssaiReviewedBy: adminUser.id,
      },
      include: moveInclude,
    });
    if (row.status === "APPROVED") {
      await copyApprovedLicence(tx, updated, adminUser);
    }
    await tx.auditLog.create({
      data: {
        adminId: adminUser.id,
        action: "KITCHEN_MOVE_FSSAI_APPROVE",
        target: row.id,
        details: JSON.stringify({ moveStatus: row.status }),
      },
    });
    return updated;
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function rejectMoveFssai({ adminUser, id, reason }) {
  const text = String(reason || "").trim();
  if (!text) throw httpError(400, "Rejection reason is required");
  if (text.length > 500) throw httpError(400, "Rejection reason is too long");
  const row = await loadMove(id);
  assertPending(row);
  if (row.fssaiStatus !== "UNDER_REVIEW") {
    throw httpError(400, "Only an FSSAI that needs review can be rejected");
  }
  const saved = await prisma.kitchenMove.update({
    where: { id: row.id },
    data: {
      fssaiStatus: "REJECTED",
      fssaiRejectionReason: text,
      fssaiReviewedAt: new Date(),
      fssaiReviewedBy: adminUser.id,
    },
    include: moveInclude,
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function approveKitchenMove({ adminUser, id }) {
  const row = await loadMove(id);
  assertPending(row);
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  if (requirementEnabled && row.fssaiStatus !== "APPROVED") {
    throw httpError(
      400,
      "Approve the FSSAI for the new society before moving this kitchen"
    );
  }
  const saved = await prisma.$transaction(async (tx) => {
    const current = await tx.kitchenMove.findUnique({ where: { id: row.id } });
    if (!current || current.status !== "PENDING") {
      throw httpError(400, "This kitchen move is already finished");
    }
    await tx.user.update({
      where: { id: row.userId },
      data: {
        societyId: row.toSocietyId,
        flatId: row.toFlatId,
        addressProofUrl: row.addressProofUrl,
        addressProofStatus: row.addressProofStatus,
        addressProofReviewedAt: row.addressProofReviewedAt,
        addressProofReviewedBy: row.addressProofReviewedBy,
      },
    });
    if (row.fssaiStatus === "APPROVED") {
      await copyApprovedLicence(tx, row, adminUser);
    }
    await tx.listing.updateMany({
      where: {
        sellerId: row.userId,
        OR: [
          { campaignId: null },
          { campaign: { status: { in: ["draft", "open"] } } },
        ],
      },
      data: { societyId: row.toSocietyId },
    });
    await tx.preOrderCampaign.updateMany({
      where: { sellerId: row.userId, status: { in: ["draft", "open"] } },
      data: { societyId: row.toSocietyId },
    });
    const updated = await tx.kitchenMove.update({
      where: { id: row.id },
      data: {
        status: "APPROVED",
        reviewedAt: new Date(),
        reviewedBy: adminUser.id,
        rejectionReason: null,
      },
      include: moveInclude,
    });
    await tx.auditLog.create({
      data: {
        adminId: adminUser.id,
        action: "KITCHEN_MOVE_APPROVE",
        target: row.id,
        details: JSON.stringify({
          fromSocietyId: row.fromSocietyId,
          toSocietyId: row.toSocietyId,
          fssaiStatus: row.fssaiStatus,
          fssaiRequired: requirementEnabled,
        }),
      },
    });
    return updated;
  });
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function rejectKitchenMove({ adminUser, id, reason }) {
  const text = String(reason || "").trim();
  if (text.length > 500) throw httpError(400, "Rejection reason is too long");
  const row = await loadMove(id);
  assertPending(row);
  const saved = await prisma.kitchenMove.update({
    where: { id: row.id },
    data: {
      status: "REJECTED",
      rejectionReason: text || null,
      reviewedAt: new Date(),
      reviewedBy: adminUser.id,
    },
    include: moveInclude,
  });
  await prisma.auditLog.create({
    data: {
      adminId: adminUser.id,
      action: "KITCHEN_MOVE_REJECT",
      target: row.id,
      details: JSON.stringify({ reason: text || null }),
    },
  });
  const requirementEnabled = await isFssaiSellingRequirementEnabled();
  return withFssaiPhoto(serializeMove(saved, requirementEnabled), saved);
}

async function getMoveFssaiDocumentUrl(id) {
  const row = await loadMove(id);
  if (!row || isAnonymizedDeletedUser(row.user)) {
    throw httpError(404, "Kitchen move not found");
  }
  if (!row.fssaiDocumentStorageReference) {
    throw httpError(404, "This move has no FSSAI document");
  }
  const url = await createSignedObjectUrl(row.fssaiDocumentStorageReference, 300);
  return { url };
}

module.exports = {
  getMyKitchenMove,
  submitKitchenMove,
  cancelMyKitchenMove,
  listKitchenMoves,
  getKitchenMove,
  reviewMoveAddressProof,
  sendMoveFssaiToReview,
  approveMoveFssai,
  rejectMoveFssai,
  approveKitchenMove,
  rejectKitchenMove,
  getMoveFssaiDocumentUrl,
};
