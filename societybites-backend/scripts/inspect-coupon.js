require("dotenv").config();
const prisma = require("../lib/prisma");
const { validateCoupon, REASONS } = require("../lib/coupons");

async function main() {
  const code = String(process.argv[2] || "PURAN50").trim().toUpperCase();
  const buyerPhone = process.argv[3];

  const coupon = await prisma.coupon.findUnique({
    where: { code },
    include: {
      eligibleSocieties: {
        include: { society: { select: { id: true, name: true, city: true } } },
      },
    },
  });

  if (!coupon) {
    console.log("Coupon not found:", code);
    process.exit(0);
  }

  console.log(
    JSON.stringify(
      {
        code: coupon.code,
        status: coupon.status,
        validFrom: coupon.validFrom,
        validUntil: coupon.validUntil,
        minimumOrderValue: coupon.minimumOrderValue,
        sellerId: coupon.sellerId,
        societies: coupon.eligibleSocieties.map((row) => row.society),
      },
      null,
      2
    )
  );

  if (buyerPhone) {
    const buyer = await prisma.user.findUnique({
      where: { phone: buyerPhone },
      select: { id: true, societyId: true, society: { select: { name: true } } },
    });
    if (!buyer) {
      console.log("Buyer not found:", buyerPhone);
    } else {
      const quote = await validateCoupon({
        code,
        userId: buyer.id,
        orderSubtotal: 250,
        sellerId: process.argv[4] || null,
      });
      console.log("validate", buyer.society?.name || buyer.societyId, quote);
    }
  }

  await prisma.$disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});