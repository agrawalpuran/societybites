/**
 * Removes address-proof queue entries left on anonymized (deleted) accounts.
 *
 *   node scripts/clear-deleted-address-proofs.js
 */
require("dotenv").config();
const prisma = require("../lib/prisma");
const {
  clearAddressProofForAnonymizedUsers,
} = require("../lib/addressProofReview");

async function main() {
  const count = await clearAddressProofForAnonymizedUsers();
  console.log(`Cleared address proof on ${count} anonymized account(s).`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
