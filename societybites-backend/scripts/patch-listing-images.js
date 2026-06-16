/**
 * Updates imageUrl on seed listings without wiping orders.
 * Run: npm run patch-listing-images
 */
const { PrismaClient } = require("@prisma/client");

const prisma = new PrismaClient();

const { setupSeedImages } = require("../lib/setupSeedImages");

const IMAGES = {
  "seed-listing-dal-makhani": "/uploads/dal-makhani.jpg",
  "seed-listing-chapati": "/uploads/chapati.jpg",
  "seed-listing-biryani": "/uploads/chicken-biryani.jpg",
  "seed-listing-paneer-masala": "/uploads/paneer-butter-masala.jpg",
  "seed-listing-lemon-rice": "/uploads/lemon-rice.jpg",
};

async function main() {
  setupSeedImages();

  for (const [id, imageUrl] of Object.entries(IMAGES)) {
    const result = await prisma.listing.updateMany({
      where: { id },
      data: { imageUrl },
    });
    console.log(`${id}: updated ${result.count} row(s)`);
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
