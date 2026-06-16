/**
 * Force-copy seed-images/*.jpg into uploads/ and bump listing updatedAt
 * so the app busts browser cache. Run: npm run sync-seed-images
 */
const { PrismaClient } = require("@prisma/client");
const { setupSeedImages } = require("../lib/setupSeedImages");

const prisma = new PrismaClient();

const SEED_LISTING_IDS = [
  "seed-listing-dal-makhani",
  "seed-listing-chapati",
  "seed-listing-biryani",
  "seed-listing-paneer-masala",
  "seed-listing-lemon-rice",
];

async function main() {
  const copied = setupSeedImages({ force: true });

  if (copied === 0) {
    console.warn("No .jpg files in seed-images/ — add photos there first.");
  }

  const now = new Date();
  for (const id of SEED_LISTING_IDS) {
    const result = await prisma.listing.updateMany({
      where: { id },
      data: { updatedAt: now },
    });
    if (result.count > 0) {
      console.log(`Refreshed cache key for ${id}`);
    }
  }

  console.log("Done. Pull to refresh in the app (or press R in Flutter).");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
