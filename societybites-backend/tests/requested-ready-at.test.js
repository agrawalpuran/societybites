require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");
const paymentRoutes = require("../routes/payments");

const SEED_BUYER_PHONE = "+919845154070";
const SEED_SELLER_PHONE = "+919901844776";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function futureIso(hoursAhead) {
  return new Date(Date.now() + hoursAhead * 60 * 60 * 1000).toISOString();
}

function jsonRequest(server, { method, path, token, body }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: addr.port,
        path,
        method,
        headers: {
          Accept: "application/json",
          ...(payload && {
            "Content-Type": "application/json",
            "Content-Length": String(payload.length),
          }),
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
    if (payload) req.write(payload);
    req.end();
  });
}

async function main() {
  const stamp = Date.now();
  const seller = await prisma.user.findUnique({ where: { phone: SEED_SELLER_PHONE } });
  const buyer = await prisma.user.findUnique({ where: { phone: SEED_BUYER_PHONE } });
  assert(seller && seller.societyId, "Seed seller with a society must exist");
  assert(buyer && buyer.societyId === seller.societyId, "Seed buyer must share the seller society");

  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);
  const listingIds = [];
  const orderIds = [];

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  app.use("/payments", paymentRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
      code: err.code,
    });
  });

  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const readyNow = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Ready now need-by ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Lunch",
        quantity: 20,
      },
    });
    assert(readyNow.status === 201, `READY_NOW create failed ${JSON.stringify(readyNow.json)}`);
    listingIds.push(readyNow.json.id);

    const made = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `MTO need-by ${stamp}`,
        price: 200,
        foodType: "VEG",
        category: "Desserts",
        quantity: 20,
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 2880,
        maxDailyOrders: 20,
      },
    });
    assert(made.status === 201, `MADE_TO_ORDER create failed ${JSON.stringify(made.json)}`);
    listingIds.push(made.json.id);

    const withoutNeedBy = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
      },
    });
    assert(withoutNeedBy.status === 201, `MTO without requestedReadyAt failed ${JSON.stringify(withoutNeedBy.json)}`);
    assert(withoutNeedBy.json.requestedReadyAt == null, "requestedReadyAt stays null when omitted");
    orderIds.push(withoutNeedBy.json.id);

    const needBy = futureIso(20);
    const withNeedBy = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
        requestedReadyAt: needBy,
      },
    });
    assert(withNeedBy.status === 201, `MTO with requestedReadyAt failed ${JSON.stringify(withNeedBy.json)}`);
    assert(withNeedBy.json.requestedReadyAt, "requestedReadyAt stored");
    assert(!withNeedBy.json.expectedReadyAt, "expectedReadyAt is not set at create");
    orderIds.push(withNeedBy.json.id);

    const pastNeedBy = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
        requestedReadyAt: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
      },
    });
    assert(pastNeedBy.status === 400, "past requestedReadyAt must be rejected");

    const readyNowNeedBy = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: readyNow.json.id, quantity: 1 }],
        requestedReadyAt: needBy,
      },
    });
    assert(readyNowNeedBy.status === 400, "Available Now must not accept requestedReadyAt");

    const buyerGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${withNeedBy.json.id}`,
      token: buyerToken,
    });
    assert(buyerGet.status === 200, "buyer can fetch order");
    assert(buyerGet.json.requestedReadyAt, "buyer sees requestedReadyAt");

    const sellerList = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller",
      token: sellerToken,
    });
    assert(sellerList.status === 200, "seller can list orders");
    const sellerRow = (sellerList.json || []).find((row) => row.id === withNeedBy.json.id);
    assert(sellerRow && sellerRow.requestedReadyAt, "seller sees requestedReadyAt");

    const accepted = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${withNeedBy.json.id}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });
    assert(accepted.status === 200, "seller can accept earlier-than-lead request");
    assert(accepted.json.status === "accepted", "accepted status");
    assert(accepted.json.requestedReadyAt, "accept does not clear requestedReadyAt");

    const readyTime = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${withNeedBy.json.id}/ready-time`,
      token: sellerToken,
      body: { expectedReadyAt: futureIso(18) },
    });
    assert(readyTime.status === 200, `ready-time failed ${JSON.stringify(readyTime.json)}`);
    assert(readyTime.json.expectedReadyAt, "expectedReadyAt set");
    assert(
      new Date(readyTime.json.requestedReadyAt).getTime() ===
        new Date(withNeedBy.json.requestedReadyAt).getTime(),
      "requestedReadyAt unchanged after seller confirmation"
    );

    const rejectTarget = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
        requestedReadyAt: futureIso(12),
      },
    });
    assert(rejectTarget.status === 201, "order to reject");
    orderIds.push(rejectTarget.json.id);

    const rejected = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${rejectTarget.json.id}/reject`,
      token: sellerToken,
      body: { reason: "Unable to fulfil by requested date" },
    });
    assert(rejected.status === 200, `reject failed ${JSON.stringify(rejected.json)}`);
    assert(rejected.json.status === "rejected", "existing reject status");
    assert(
      String(rejected.json.rejectReason || "").includes("Unable to fulfil by requested date"),
      "existing rejection reason stored"
    );

    const existingGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${withoutNeedBy.json.id}`,
      token: buyerToken,
    });
    assert(existingGet.status === 200, "existing order without requestedReadyAt still loads");
    assert(existingGet.json.requestedReadyAt == null, "legacy orders keep null requestedReadyAt");

    const upiListing = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `UPI need-by ${stamp}`,
        price: 80,
        foodType: "VEG",
        category: "Desserts",
        quantity: 10,
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 60,
      },
    });
    assert(upiListing.status === 201, "UPI MTO listing");
    listingIds.push(upiListing.json.id);

    const upiOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "upi",
        items: [{ listingId: upiListing.json.id, quantity: 1 }],
        requestedReadyAt: futureIso(6),
      },
    });
    assert(upiOrder.status === 201, `UPI flow create failed ${JSON.stringify(upiOrder.json)}`);
    orderIds.push(upiOrder.json.id);

    const upiAccepted = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });
    assert(upiAccepted.status === 200, "UPI accept still works");

    const markPaid = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiOrder.json.id}/mark-paid`,
      token: buyerToken,
      body: {},
    });
    assert(markPaid.status === 200, `I've Paid failed ${JSON.stringify(markPaid.json)}`);

    const confirm = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiOrder.json.id}/confirm`,
      token: sellerToken,
      body: { readyInMinutes: 45 },
    });
    assert(confirm.status === 200, `UPI confirm failed ${JSON.stringify(confirm.json)}`);
    assert(confirm.json.requestedReadyAt, "UPI confirm keeps requestedReadyAt");
    assert(confirm.json.expectedReadyAt, "UPI confirm still sets expectedReadyAt");

    const cashOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
      },
    });
    assert(cashOrder.status === 201, `COD flow create failed ${JSON.stringify(cashOrder.json)}`);
    orderIds.push(cashOrder.json.id);

    const cashAccepted = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${cashOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });
    assert(cashAccepted.status === 200, "COD accept still works");
    assert(cashAccepted.json.paymentMethod === "cash", "COD payment method unchanged");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (orderIds.length) {
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    await prisma.$disconnect();
  }
}

main()
  .then(() => {
    console.log("requested-ready-at tests passed");
    process.exit(0);
  })
  .catch(async (err) => {
    console.error(err);
    await prisma.$disconnect();
    process.exit(1);
  });
