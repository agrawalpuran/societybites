const assert = require("node:assert/strict");
const prisma = require("../lib/prisma");
const {
  normalizeSlug,
  assertValidStorefrontSlug,
  getKitchenBySlug,
} = require("../lib/storefront");

async function main() {
  assert(normalizeSlug(" Puran ") === "puran");
  assert.throws(() => assertValidStorefrontSlug("www"), /reserved/i);

  const stamp = Date.now().toString().slice(-8);
  const phone = `+9177${stamp}99`;
  const seller = await prisma.user.create({
    data: {
      phone,
      name: "Puran Test",
      role: "seller",
      storefrontSlug: `puran-test-${stamp}`,
      storefrontAccentColor: "#112233",
      storefrontTagline: "Homemade with love",
    },
  });

  const society = await prisma.society.create({
    data: {
      name: `Slug Society ${stamp}`,
      city: "bengaluru",
      address: "Test",
    },
  });

  await prisma.user.update({
    where: { id: seller.id },
    data: { societyId: society.id },
  });

  const listing = await prisma.listing.create({
    data: {
      sellerId: seller.id,
      societyId: society.id,
      name: "Test Dish",
      price: 100,
      quantity: 5,
      status: "active",
      catalogType: "REGULAR",
    },
  });

  assert(listing.id);

  const payload = await getKitchenBySlug(`puran-test-${stamp}`);
  assert(payload.slug === `puran-test-${stamp}`);
  assert(payload.seller.id === seller.id);
  assert(payload.branding.accentColor === "#112233");
  assert(payload.listings.some((row) => row.name === "Test Dish"));
  assert(payload.listings[0].sellerPaymentPreference != null);

  await prisma.listing.delete({ where: { id: listing.id } });
  await prisma.user.delete({ where: { id: seller.id } });
  await prisma.society.delete({ where: { id: society.id } });

  console.log("storefront-slug.test.js: PASS");
}

main()
  .catch((error) => {
    console.error("storefront-slug.test.js: FAIL");
    console.error(error);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
