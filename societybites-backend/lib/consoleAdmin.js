const prisma = require("./prisma");

const SELLER_ROLES = new Set(["seller", "super_admin"]);

/**
 * Legacy console grant set role=admin and removed seller from nearby discovery.
 * Restore seller role when the account still behaves like a kitchen.
 */
async function repairLegacyConsoleAdminSeller(user, include = {}) {
  if (!user || user.role !== "admin" || user.consoleAdmin === true) {
    return user;
  }

  const listingCount = await prisma.listing.count({
    where: { sellerId: user.id },
  });
  const reach = String(user.sellingReachLevel || "");
  const looksLikeSeller =
    listingCount > 0 || reach === "NEARBY" || reach === "EXTENDED";

  if (!looksLikeSeller) {
    return prisma.user.update({
      where: { id: user.id },
      data: { consoleAdmin: true },
      include,
    });
  }

  return prisma.user.update({
    where: { id: user.id },
    data: { role: "seller", consoleAdmin: true },
    include,
  });
}

function isConsoleAdminUser(user) {
  if (!user) return false;
  if (user.consoleAdmin === true) return true;
  return user.role === "admin";
}

module.exports = {
  repairLegacyConsoleAdminSeller,
  isConsoleAdminUser,
  SELLER_ROLES,
};
