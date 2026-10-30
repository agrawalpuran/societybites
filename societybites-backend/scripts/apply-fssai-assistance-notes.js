/**
 * One-shot: add FssaiAssistanceRequest.notes if missing.
 * Usage: node scripts/apply-fssai-assistance-notes.js
 */
require("dotenv").config();
const { PrismaClient } = require("@prisma/client");

async function main() {
  const prisma = new PrismaClient();
  try {
    await prisma.$executeRawUnsafe(
      'ALTER TABLE "FssaiAssistanceRequest" ADD COLUMN IF NOT EXISTS "notes" TEXT'
    );
    const rows = await prisma.$queryRawUnsafe(`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'FssaiAssistanceRequest'
        AND column_name = 'notes'
    `);
    console.log("OK — FssaiAssistanceRequest.notes is present:");
    console.log(rows);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
