require("dotenv").config();
const prisma = require("../lib/prisma");
const {
  aggregateOrders,
  resolvePerformanceRange,
} = require("../lib/adminSellerPerformance");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sampleOrder(overrides = {}) {
  return {
    id: "o1",
    buyerId: "b1",
    status: "completed",
    subtotal: 200,
    deliveryCharge: 30,
    communityFee: 0,
    total: 230,
    paymentMethod: "upi",
    paymentStatus: "paid",
    createdAt: new Date("2026-09-10T10:00:00.000Z"),
    couponRedemptions: [],
    items: [
      {
        listing: {
          sellerId: "s1",
          seller: { id: "s1", name: "Kitchen A", phone: "+911111111111" },
        },
      },
    ],
    ...overrides,
  };
}

async function main() {
  const range = resolvePerformanceRange({ preset: "last_7_days" });
  assert(range.fromYmd && range.toYmd, "range resolves");

  const allTime = resolvePerformanceRange({ preset: "all_time" });
  assert(allTime.preset === "all_time", "all_time preset");

  const { summary, bySeller } = aggregateOrders([
    sampleOrder(),
    sampleOrder({
      id: "o2",
      status: "cancelled",
      buyerId: "b2",
      subtotal: 100,
    }),
    sampleOrder({
      id: "o3",
      subtotal: 150,
      couponRedemptions: [{ status: "REDEEMED", discountAmount: 50 }],
    }),
  ]);

  assert(summary.qualifyingOrders === 2, "completed only in qualifying count");
  assert(summary.grossFoodSales === 350, "gross food sums subtotals");
  assert(summary.netFoodSales === 300, "net food subtracts coupon");
  assert(summary.deliveryCharges === 60, "delivery separate");
  const seller = bySeller.get("s1");
  assert(seller.ordersCreated === 3, "all orders counted for rate");
  assert(seller.cancelledCount === 1, "cancelled tracked");

  console.log("admin-seller-performance.test.js passed");
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
