const prisma = require("./prisma");
const { isAnonymizedDeletedUser } = require("./accountDeletion");

const ADDRESS_PROOF_STATUSES = ["PENDING", "OK", "FOLLOW_UP"];

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function displayStatus(status) {
  return status || "PENDING";
}

function proofWhere(status) {
  const hasPhoto = { addressProofUrl: { not: null } };
  const requested = String(status || "PENDING").trim().toUpperCase();
  if (requested === "ALL") return hasPhoto;
  if (requested === "PENDING") {
    return {
      AND: [
        hasPhoto,
        { OR: [{ addressProofStatus: null }, { addressProofStatus: "PENDING" }] },
      ],
    };
  }
  if (requested === "OK" || requested === "FOLLOW_UP") {
    return { AND: [hasPhoto, { addressProofStatus: requested }] };
  }
  throw httpError(400, "Invalid address proof status");
}

const userInclude = {
  society: { select: { name: true, city: true } },
  flat: { select: { block: true, flatNumber: true } },
};

function serializeSummary(user) {
  return {
    userId: user.id,
    name: user.name || "Seller",
    phone: user.phone || null,
    role: user.role,
    societyName: user.society?.name || null,
    societyCity: user.society?.city || null,
    block: user.flat?.block || null,
    flatNumber: user.flat?.flatNumber || null,
    status: displayStatus(user.addressProofStatus),
    reviewedAt: user.addressProofReviewedAt,
    reviewedBy: user.addressProofReviewedBy,
  };
}

function serializeDetail(user) {
  return {
    ...serializeSummary(user),
    addressProofUrl: user.addressProofUrl,
  };
}

async function listAddressProofs({ status } = {}) {
  const users = await prisma.user.findMany({
    where: proofWhere(status),
    include: userInclude,
    orderBy: { createdAt: "desc" },
  });
  return users
    .filter((user) => !isAnonymizedDeletedUser(user))
    .map(serializeSummary);
}

async function getAddressProof(userId) {
  const user = await prisma.user.findUnique({
    where: { id: String(userId) },
    include: userInclude,
  });
  if (!user || !user.addressProofUrl || isAnonymizedDeletedUser(user)) {
    throw httpError(404, "Address proof not found");
  }
  return serializeDetail(user);
}

async function reviewAddressProof({ adminUser, userId, status }) {
  const next = String(status || "").trim().toUpperCase();
  if (next !== "OK" && next !== "FOLLOW_UP") {
    throw httpError(400, "Invalid address proof status");
  }
  const user = await prisma.user.findUnique({
    where: { id: String(userId) },
    include: userInclude,
  });
  if (!user || !user.addressProofUrl || isAnonymizedDeletedUser(user)) {
    throw httpError(404, "Address proof not found");
  }
  const from = displayStatus(user.addressProofStatus);
  const updated = await prisma.$transaction(async (tx) => {
    const row = await tx.user.update({
      where: { id: user.id },
      data: {
        addressProofStatus: next,
        addressProofReviewedAt: new Date(),
        addressProofReviewedBy: adminUser.id,
      },
      include: userInclude,
    });
    await tx.auditLog.create({
      data: {
        adminId: adminUser.id,
        action: "ADDRESS_PROOF_REVIEW",
        target: user.id,
        details: JSON.stringify({ from, to: next }),
      },
    });
    return row;
  });
  return serializeDetail(updated);
}

/** Clears address-proof fields left on anonymized accounts (legacy rows). */
async function clearAddressProofForAnonymizedUsers() {
  const result = await prisma.user.updateMany({
    where: {
      phone: { startsWith: "deleted_" },
      addressProofUrl: { not: null },
    },
    data: {
      addressProofUrl: null,
      addressProofStatus: null,
      addressProofReviewedAt: null,
      addressProofReviewedBy: null,
    },
  });
  return result.count;
}

module.exports = {
  ADDRESS_PROOF_STATUSES,
  listAddressProofs,
  getAddressProof,
  reviewAddressProof,
  clearAddressProofForAnonymizedUsers,
};
