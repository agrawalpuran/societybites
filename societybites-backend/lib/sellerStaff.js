const { normalizeIndianPhone } = require("../utils/phone");
const { canonicalTestPhone } = require("./testOtp");

const STAFF_ROLE_OWNER = "owner";
const STAFF_STATUS_ACTIVE = "active";

/** Product MVP: owner = view-only oversight of a manager's kitchen. */
const VIEW_ONLY_ROLES = new Set([STAFF_ROLE_OWNER]);

function resolveInvitePhone(raw) {
  return normalizeIndianPhone(raw) || canonicalTestPhone(raw);
}

function serializeMembership(row) {
  if (!row) return null;
  return {
    id: row.id,
    sellerUserId: row.sellerUserId,
    staffUserId: row.staffUserId,
    role: row.role,
    status: row.status,
    createdAt: row.createdAt,
    sellerName: row.seller?.name || null,
    sellerPhone: row.seller?.phone || null,
    staffName: row.staff?.name || null,
    staffPhone: row.staff?.phone || null,
    viewOnly: VIEW_ONLY_ROLES.has(row.role),
  };
}

/**
 * Kitchens the user may oversee (staff side). Additive for /auth/me.
 */
async function listStaffAccessForUser(prisma, staffUserId) {
  const rows = await prisma.sellerStaffMembership.findMany({
    where: {
      staffUserId,
      status: STAFF_STATUS_ACTIVE,
      role: STAFF_ROLE_OWNER,
    },
    include: {
      seller: { select: { id: true, name: true, phone: true } },
    },
    orderBy: { createdAt: "asc" },
  });
  return rows.map((row) => ({
    membershipId: row.id,
    sellerUserId: row.sellerUserId,
    sellerName: row.seller?.name || "Store",
    sellerPhone: row.seller?.phone || null,
    role: row.role,
    viewOnly: true,
  }));
}

/** Owners invited by this kitchen principal (manager list UI). */
async function listOwnersForSeller(prisma, sellerUserId) {
  const rows = await prisma.sellerStaffMembership.findMany({
    where: {
      sellerUserId,
      status: STAFF_STATUS_ACTIVE,
      role: STAFF_ROLE_OWNER,
    },
    include: {
      staff: { select: { id: true, name: true, phone: true } },
    },
    orderBy: { createdAt: "asc" },
  });
  return rows.map(serializeMembership);
}

async function findActiveOwnerMembership(prisma, staffUserId, sellerUserId) {
  if (!staffUserId || !sellerUserId) return null;
  return prisma.sellerStaffMembership.findFirst({
    where: {
      staffUserId,
      sellerUserId,
      status: STAFF_STATUS_ACTIVE,
      role: STAFF_ROLE_OWNER,
    },
  });
}

async function canViewKitchenAsOwner(prisma, staffUserId, sellerUserId) {
  const row = await findActiveOwnerMembership(prisma, staffUserId, sellerUserId);
  return Boolean(row);
}

async function canViewOrderAsOwnerStaff(prisma, userId, order) {
  if (!order || !userId) return false;
  const sellerIds = new Set(
    (order.items || [])
      .map((item) => item.listing && item.listing.sellerId)
      .filter(Boolean)
  );
  if (sellerIds.size === 0) return false;
  for (const sellerUserId of sellerIds) {
    if (await canViewKitchenAsOwner(prisma, userId, sellerUserId)) {
      return true;
    }
  }
  return false;
}

/**
 * Invite owner by phone. Creates a buyer user if the phone is new so OTP login
 * later attaches to the same row. No revoke in MVP.
 */
function canManageOwnerAccess(user) {
  return Boolean(user && (user.role === "seller" || user.role === "super_admin"));
}

async function inviteOwnerByPhone(prisma, { sellerUser, phoneRaw }) {
  if (!canManageOwnerAccess(sellerUser)) {
    const err = new Error("Only sellers can invite an owner");
    err.statusCode = 403;
    err.code = "SELLER_REQUIRED";
    throw err;
  }

  const phone = resolveInvitePhone(phoneRaw);
  if (!phone) {
    const err = new Error("Enter a valid Indian mobile number");
    err.statusCode = 400;
    throw err;
  }

  if (phone === sellerUser.phone) {
    const err = new Error("You cannot invite your own number as owner");
    err.statusCode = 400;
    throw err;
  }

  let staff = await prisma.user.findUnique({ where: { phone } });
  if (!staff) {
    staff = await prisma.user.create({
      data: { phone, role: "buyer" },
    });
  }

  if (staff.id === sellerUser.id) {
    const err = new Error("You cannot invite your own account as owner");
    err.statusCode = 400;
    throw err;
  }

  const existing = await prisma.sellerStaffMembership.findUnique({
    where: {
      sellerUserId_staffUserId: {
        sellerUserId: sellerUser.id,
        staffUserId: staff.id,
      },
    },
  });

  if (existing && existing.status === STAFF_STATUS_ACTIVE) {
    const err = new Error("This number already has owner access to your store");
    err.statusCode = 409;
    throw err;
  }

  if (existing) {
    const updated = await prisma.sellerStaffMembership.update({
      where: { id: existing.id },
      data: {
        role: STAFF_ROLE_OWNER,
        status: STAFF_STATUS_ACTIVE,
      },
      include: {
        seller: { select: { id: true, name: true, phone: true } },
        staff: { select: { id: true, name: true, phone: true } },
      },
    });
    return serializeMembership(updated);
  }

  const created = await prisma.sellerStaffMembership.create({
    data: {
      sellerUserId: sellerUser.id,
      staffUserId: staff.id,
      role: STAFF_ROLE_OWNER,
      status: STAFF_STATUS_ACTIVE,
    },
    include: {
      seller: { select: { id: true, name: true, phone: true } },
      staff: { select: { id: true, name: true, phone: true } },
    },
  });
  return serializeMembership(created);
}

module.exports = {
  STAFF_ROLE_OWNER,
  STAFF_STATUS_ACTIVE,
  resolveInvitePhone,
  serializeMembership,
  listStaffAccessForUser,
  listOwnersForSeller,
  findActiveOwnerMembership,
  canViewKitchenAsOwner,
  canViewOrderAsOwnerStaff,
  canManageOwnerAccess,
  inviteOwnerByPhone,
};
