require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");
const {
  resolveDateRange,
  computeInsights,
  addDaysYmd,
  formatIstYmd,
} = require("../lib/sellerInsights");

const SEED_BUYER_PHONE = "+919845154070";
const SEED_SELLER_PHONE = "+919901844776";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: addr.port,
        path,
        method,
        headers: {
          Accept: "application/json",
          ...(token && { Authorization: `Bearer ${token}` }),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {}
          resolve({ status: res.statusCode, json });
        });
      }
    );
    req.on("error", reject);
    req.end();
  });
}

async function main() {
  const today = formatIstYmd(new Date("2026-09-23T12:00:00+05:30"));
  const last7 = resolveDateRange({
    preset: "last_7_days",
    now: new Date("2026-09-23T12:00:00+05:30"),
  });
  assert(last7.fromYmd === addDaysYmd(today, -6), "last 7 days starts 6 days before today");
  assert(last7.toYmd === today, "last 7 days ends today inclusive");
  assert(last7.endInclusive === true, "end date is inclusive");

  const thisMonth = resolveDateRange({
    preset: "this_month",
    now: new Date("2026-09-23T00:15:00+05:30"),
  });
  assert(thisMonth.fromYmd === "2026-09-01", "this month starts on the 1st IST");

  const custom = resolveDateRange({
    from: "2026-09-01",
    to: "2026-09-23",
  });
  assert(custom.preset === "custom", "from+to without preset is custom");
  assert(custom.from.toISOString() === "2026-08-31T18:30:00.000Z", "IST midnight start");
  assert(custom.to.toISOString() === "2026-09-23T18:29:59.999Z", "IST end-of-day inclusive");

  try {
    resolveDateRange({ from: "2026-09-10", to: "2026-09-01" });
    throw new Error("expected inverted range error");
  } catch (err) {
    assert(err.statusCode === 400, "inverted custom range is 400");
  }

  const computed = computeInsights({
    sellerId: "seller-a",
    range: last7,
    lifetimeOrderCount: 3,
    orders: [
      {
        id: "1",
        orderNumber: "SB-1",
        status: "completed",
        createdAt: new Date("2026-09-22T10:00:00+05:30"),
        buyer: { name: "Asha" },
        items: [
          {
            listingId: "dhokla",
            quantity: 2,
            unitPrice: 100,
            listing: { id: "dhokla", name: "Dad's Dhokla", sellerId: "seller-a" },
          },
        ],
      },
      {
        id: "2",
        orderNumber: "SB-2",
        status: "cancelled",
        createdAt: new Date("2026-09-22T11:00:00+05:30"),
        buyer: { name: "Ravi" },
        items: [
          {
            listingId: "dhokla",
            quantity: 9,
            unitPrice: 100,
            listing: { id: "dhokla", name: "Dad's Dhokla", sellerId: "seller-a" },
          },
        ],
      },
      {
        id: "3",
        orderNumber: "SB-3",
        status: "pending",
        createdAt: new Date("2026-09-23T09:00:00+05:30"),
        buyer: { name: "Meera" },
        items: [
          {
            listingId: "pickle",
            quantity: 1,
            unitPrice: 50,
            listing: { id: "pickle", name: "Gungoura Pickle", sellerId: "seller-a" },
          },
        ],
      },
    ],
  });

  assert(computed.summary.orders === 3, "all statuses count as orders");
  assert(computed.summary.sales === 200, "cancelled orders are not sales");
  assert(computed.summary.itemsSold === 2, "items sold come from completed quantities");
  assert(computed.summary.averageOrderValue === 200, "AOV uses completed orders only");
  assert(computed.topItems[0].name === "Dad's Dhokla", "top item uses completed qty");
  assert(computed.topItems[0].quantitySold === 2, "cancelled qty excluded from top items");
  assert(!computed.topItems.some((item) => item.name === "Gungoura Pickle"), "pending not in top items");
  assert(computed.statusBreakdown.find((row) => row.status === "cancelled").count === 1, "cancelled in breakdown");
  assert(computed.empty === null, "period with orders is not empty");

  const emptyPeriod = computeInsights({
    sellerId: "seller-a",
    range: last7,
    lifetimeOrderCount: 4,
    orders: [],
  });
  assert(emptyPeriod.empty === "period", "lifetime orders + empty range is period empty");

  const neverSold = computeInsights({
    sellerId: "seller-a",
    range: last7,
    lifetimeOrderCount: 0,
    orders: [],
  });
  assert(neverSold.empty === "none", "no lifetime orders");

  const seller = await prisma.user.findUnique({ where: { phone: SEED_SELLER_PHONE } });
  const buyer = await prisma.user.findUnique({ where: { phone: SEED_BUYER_PHONE } });
  assert(seller && buyer, "seed seller and buyer required");

  const stamp = Date.now();
  const created = { listingIds: [], orderIds: [], userIds: [] };

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  try {
    const otherSeller = await prisma.user.create({
      data: {
        phone: `+9198${String(stamp).slice(-8)}`,
        name: "Other Seller",
        role: "seller",
        societyId: seller.societyId,
      },
    });
    created.userIds.push(otherSeller.id);

    const listingA = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Insights Dhokla ${stamp}`,
        price: 120,
        quantity: 20,
        status: "active",
      },
    });
    created.listingIds.push(listingA.id);

    const listingB = await prisma.listing.create({
      data: {
        sellerId: otherSeller.id,
        societyId: seller.societyId,
        name: `Insights Secret ${stamp}`,
        price: 999,
        quantity: 20,
        status: "active",
      },
    });
    created.listingIds.push(listingB.id);

    const completedA = await prisma.order.create({
      data: {
        orderNumber: `INS-A-${stamp}`,
        buyerId: buyer.id,
        societyId: seller.societyId,
        status: "completed",
        subtotal: 240,
        total: 240,
        createdAt: new Date(),
        completedAt: new Date(),
        items: {
          create: [{ listingId: listingA.id, quantity: 2, unitPrice: 120 }],
        },
      },
    });
    created.orderIds.push(completedA.id);

    const cancelledA = await prisma.order.create({
      data: {
        orderNumber: `INS-C-${stamp}`,
        buyerId: buyer.id,
        societyId: seller.societyId,
        status: "cancelled",
        subtotal: 120,
        total: 120,
        cancelledAt: new Date(),
        items: {
          create: [{ listingId: listingA.id, quantity: 1, unitPrice: 120 }],
        },
      },
    });
    created.orderIds.push(cancelledA.id);

    const completedB = await prisma.order.create({
      data: {
        orderNumber: `INS-B-${stamp}`,
        buyerId: buyer.id,
        societyId: seller.societyId,
        status: "completed",
        subtotal: 999,
        total: 999,
        completedAt: new Date(),
        items: {
          create: [{ listingId: listingB.id, quantity: 5, unitPrice: 999 }],
        },
      },
    });
    created.orderIds.push(completedB.id);

    const unauth = await jsonRequest(server, {
      method: "GET",
      path: "/orders/seller/insights",
    });
    assert(unauth.status === 401, "insights require auth");

    const sellerToken = signToken(seller);
    const otherToken = signToken(otherSeller);
    const buyerToken = signToken(buyer);

    const sellerRes = await jsonRequest(server, {
      method: "GET",
      path: "/orders/seller/insights?preset=last_7_days",
      token: sellerToken,
    });
    assert(sellerRes.status === 200, `seller insights ${sellerRes.status}`);
    assert(sellerRes.json.summary.sales >= 240, "seller A sales include completed A");
    assert(
      sellerRes.json.recentOrders.every((row) => row.orderNumber !== `INS-B-${stamp}`),
      "seller A must never see seller B orders"
    );
    assert(
      !sellerRes.json.topItems.some((item) => item.listingId === listingB.id),
      "seller A must never see seller B items"
    );
    const cancelledRow = sellerRes.json.statusBreakdown.find((row) => row.status === "cancelled");
    assert(cancelledRow && cancelledRow.count >= 1, "cancelled appears in status breakdown");
    assert(
      !sellerRes.json.topItems.some((item) => item.listingId === listingA.id && item.quantitySold < 2),
      "top item qty is completed only"
    );

    const otherRes = await jsonRequest(server, {
      method: "GET",
      path: "/orders/seller/insights?preset=last_7_days",
      token: otherToken,
    });
    assert(otherRes.status === 200, "other seller insights");
    assert(otherRes.json.summary.sales === 4995, "seller B sees only own completed sales");
    assert(
      otherRes.json.recentOrders.every((row) => row.orderNumber !== `INS-A-${stamp}`),
      "seller B must never see seller A orders"
    );

    const buyerRes = await jsonRequest(server, {
      method: "GET",
      path: "/orders/seller/insights",
      token: buyerToken,
    });
    assert(buyerRes.status === 200, "authenticated buyer can call insights for own id");
    assert(
      buyerRes.json.recentOrders.every((row) => row.orderNumber !== `INS-A-${stamp}`),
      "buyer token does not receive another seller's orders"
    );

    const listingRes = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${listingA.id}`,
      token: buyerToken,
    });
    assert(listingRes.status === 200, "listing detail");
    assert(listingRes.json.quantitySold === 2, "public sold count is completed qty only");
    assert(listingRes.json.quantity === 20, "inventory quantity is unchanged");

    const zeroListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Insights Unsold ${stamp}`,
        price: 10,
        quantity: 3,
        status: "active",
      },
    });
    created.listingIds.push(zeroListing.id);
    const zeroRes = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${zeroListing.id}`,
      token: buyerToken,
    });
    assert(zeroRes.json.quantitySold === 0, "listing with zero sales reports 0 sold");

    const badRange = await jsonRequest(server, {
      method: "GET",
      path: "/orders/seller/insights?preset=custom&from=2026-09-10&to=2026-09-01",
      token: sellerToken,
    });
    assert(badRange.status === 400, "invalid custom range is 400");
  } finally {
    server.close();
    if (created.orderIds.length) {
      await prisma.order.deleteMany({ where: { id: { in: created.orderIds } } });
    }
    if (created.listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: created.listingIds } } });
    }
    if (created.userIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: created.userIds } } });
    }
  }

  console.log("seller-insights.test.js passed");
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
