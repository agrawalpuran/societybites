/**
 * Upload existing local /uploads files to Supabase Storage and rewrite DB URLs.
 * Run from societybites-backend after setting SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY:
 *   node scripts/migrate-uploads-to-supabase.js
 */
require("dotenv").config();
const fs = require("fs");
const path = require("path");
const prisma = require("../lib/prisma");
const {
  isObjectStorageConfigured,
  uploadLocalFile,
} = require("../lib/objectStorage");

const UPLOADS_DIR = path.join(__dirname, "..", "uploads");

function localPathFromUrl(imageUrl) {
  if (!imageUrl || typeof imageUrl !== "string") return null;
  if (!imageUrl.startsWith("/uploads/")) return null;
  const filename = path.basename(imageUrl);
  if (!filename || filename.includes("..")) return null;
  return path.join(UPLOADS_DIR, filename);
}

function mimeFromFilename(filename) {
  if (filename.endsWith(".png")) return "image/png";
  if (filename.endsWith(".webp")) return "image/webp";
  return "image/jpeg";
}

async function migrateRows(label, rows, update) {
  let migrated = 0;
  let skipped = 0;
  let missing = 0;

  for (const row of rows) {
    const filePath = localPathFromUrl(row.imageUrl);
    if (!filePath) {
      skipped += 1;
      continue;
    }
    if (!fs.existsSync(filePath)) {
      console.warn(`Missing local file for ${label} ${row.id}: ${row.imageUrl}`);
      missing += 1;
      continue;
    }
    const publicUrl = await uploadLocalFile({
      filePath,
      mimeType: mimeFromFilename(filePath),
      userId: row.sellerId || "seed",
      prefix: label,
    });
    await update(row.id, publicUrl);
    console.log(`Updated ${label} ${row.id} -> ${publicUrl}`);
    migrated += 1;
  }

  return { migrated, skipped, missing };
}

async function main() {
  if (!isObjectStorageConfigured()) {
    throw new Error(
      "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY before migrating images."
    );
  }

  const listings = await prisma.listing.findMany({
    where: { imageUrl: { startsWith: "/uploads/" } },
    select: { id: true, imageUrl: true, sellerId: true },
  });
  const campaigns = await prisma.preOrderCampaign.findMany({
    where: { coverImageUrl: { startsWith: "/uploads/" } },
    select: { id: true, coverImageUrl: true, sellerId: true },
  });

  const listingResult = await migrateRows(
    "listings",
    listings,
    (id, imageUrl) => prisma.listing.update({ where: { id }, data: { imageUrl } })
  );
  const campaignResult = await migrateRows(
    "campaigns",
    campaigns.map((campaign) => ({
      ...campaign,
      imageUrl: campaign.coverImageUrl,
    })),
    (id, imageUrl) =>
      prisma.preOrderCampaign.update({
        where: { id },
        data: { coverImageUrl: imageUrl },
      })
  );

  console.log("Listing image migration:", listingResult);
  console.log("Campaign cover migration:", campaignResult);
}

main()
  .catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
