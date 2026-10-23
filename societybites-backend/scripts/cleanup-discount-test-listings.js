/**
 * Removes listing-discount-api leftovers (Discount dish/sizes/pool/coupon).
 * Seed buyer/seller accounts are not deleted.
 *
 *   node scripts/cleanup-discount-test-listings.js
 *   node scripts/cleanup-discount-test-listings.js --apply
 */
require("dotenv").config();
const prisma = require("../lib/prisma");

const DISCOUNT_TEST_NAME = /^Discount (dish|sizes|pool|coupon) \d/;

async function collect() {
  const named = await prisma.listing.findMany({
    select: { id: true, name: true, variantGroupId: true },
  });
  const matched = named.filter((row) => DISCOUNT_TEST_NAME.test(row.name || ""));
  const groupIds = [
    ...new Set(matched.map((row) => row.variantGroupId).filter(Boolean)),
  ];
  const siblings = groupIds.length
    ? await prisma.listing.findMany({
        where: { variantGroupId: { in: groupIds } },
        select: { id: true, name: true, variantGroupId: true },
      })
    : [];
  const listings = [
    ...new Map([...matched, ...siblings].map((row) => [row.id, row])).values(),
  ];
  const listingIds = listings.map((row) => row.id);

  const orderItems = listingIds.length
    ? await prisma.orderItem.findMany({
        where: { listingId: { in: listingIds } },
        select: { orderId: true },
      })
    : [];
  const orderIds = [...new Set(orderItems.map((item) => item.orderId))];

  const redemptions = orderIds.length
    ? await prisma.couponRedemption.findMany({
        where: { orderId: { in: orderIds } },
        select: { couponId: true },
      })
    : [];
  const couponIds = [...new Set(redemptions.map((row) => row.couponId))];

  return { listings, listingIds, orderIds, couponIds };
}

async function apply(plan) {
  const { listingIds, orderIds, couponIds } = plan;
  if (orderIds.length) {
    await prisma.message.deleteMany({ where: { orderId: { in: orderIds } } });
    await prisma.review.deleteMany({ where: { orderId: { in: orderIds } } });
    await prisma.couponRedemption.deleteMany({
      where: { orderId: { in: orderIds } },
    });
    await prisma.orderIdempotency.deleteMany({
      where: { orderId: { in: orderIds } },
    });
    await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } });
    await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
  }
  if (couponIds.length) {
    await prisma.couponRedemption.deleteMany({
      where: { couponId: { in: couponIds } },
    });
    await prisma.coupon.deleteMany({ where: { id: { in: couponIds } } });
  }
  if (listingIds.length) {
    await prisma.review.deleteMany({ where: { listingId: { in: listingIds } } });
    await prisma.orderItem.deleteMany({
      where: { listingId: { in: listingIds } },
    });
    await prisma.listing.updateMany({
      where: { sourceListingId: { in: listingIds } },
      data: { sourceListingId: null },
    });
    await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
  }
}

async function main() {
  const plan = await collect();
  const byName = {};
  for (const listing of plan.listings) {
    const key = listing.name.replace(/\d{6,}/g, "#");
    byName[key] = (byName[key] || 0) + 1;
  }
  console.log(`listings ${plan.listings.length}`);
  for (const [name, count] of Object.entries(byName).sort()) {
    console.log(`  listing: ${count} x ${name}`);
  }
  console.log(`orders ${plan.orderIds.length}`);
  console.log(`coupons ${plan.couponIds.length}`);

  if (!process.argv.includes("--apply")) {
    console.log("dry run only");
    return;
  }
  await apply(plan);
  const after = await collect();
  console.log(
    `remaining listings ${after.listings.length} orders ${after.orderIds.length}`
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
