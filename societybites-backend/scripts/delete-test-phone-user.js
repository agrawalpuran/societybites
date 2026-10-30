/**
 * One-off: anonymize a test user by phone so the number can register again.
 * Usage: node scripts/delete-test-phone-user.js 5555555555
 */
require("dotenv").config();
const { deleteAuthenticatedAccount } = require("../lib/accountDeletion");
const prisma = require("../lib/prisma");

async function main() {
  const raw = String(process.argv[2] || "5555555555").replace(/\D/g, "");
  if (raw.length < 10) {
    console.error("Pass a 10-digit phone, e.g. 5555555555");
    process.exit(1);
  }
  const last10 = raw.slice(-10);
  const phones = [`+91${last10}`, last10, `+91 ${last10}`];

  const users = await prisma.user.findMany({
    where: {
      OR: [
        { phone: { in: phones } },
        { phone: { endsWith: last10 } },
        { name: { equals: "test5", mode: "insensitive" } },
      ],
    },
    select: { id: true, phone: true, name: true, role: true, suspended: true },
  });

  console.log("FOUND", JSON.stringify(users, null, 2));
  if (!users.length) {
    console.log("No matching user.");
    return;
  }

  for (const u of users) {
    const r = await deleteAuthenticatedAccount(u.id);
    console.log("DELETED", u.phone, r);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
