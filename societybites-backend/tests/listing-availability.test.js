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
        name: `Ready now ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Lunch",
        quantity: 20,
      },
    });
    assert(readyNow.status === 201, `READY_NOW create failed ${JSON.stringify(readyNow.json)}`);
    assert(readyNow.json.catalogType === "REGULAR", "READY_NOW stays REGULAR");
    assert(readyNow.json.availabilityMode === "READY_NOW", "default availabilityMode");
    listingIds.push(readyNow.json.id);

    const preorder = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Preorder ${stamp}`,
        price: 90,
        foodType: "VEG",
        category: "Dinner",
        catalogType: "PREORDER",
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 60,
      },
    });
    assert(preorder.status === 400, "PREORDER cannot be MADE_TO_ORDER");

    const preorderOk = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Preorder ok ${stamp}`,
        price: 90,
        foodType: "VEG",
        category: "Dinner",
        catalogType: "PREORDER",
      },
    });
    assert(preorderOk.status === 201, "PREORDER create still works");
    assert(preorderOk.json.catalogType === "PREORDER", "PREORDER catalog unchanged");
    assert(preorderOk.json.availabilityMode === "READY_NOW", "PREORDER availability READY_NOW");
    listingIds.push(preorderOk.json.id);

    const invalidMode = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bad mode ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Snacks",
        availabilityMode: "CUSTOM",
      },
    });
    assert(invalidMode.status === 400, "invalid availabilityMode must be 400");

    const missingPrep = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Missing prep ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Snacks",
        availabilityMode: "MADE_TO_ORDER",
      },
    });
    assert(missingPrep.status === 400, "MADE_TO_ORDER without prep must be 400");

    const badPrep = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bad prep ${stamp}`,
        price: 40,
        foodType: "VEG",
        category: "Snacks",
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 5,
      },
    });
    assert(badPrep.status === 400, "short prep time must be 400");

    const made = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Cake ${stamp}`,
        price: 650,
        foodType: "VEG",
        category: "Desserts",
        quantity: 20,
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 240,
        maxDailyOrders: 1,
      },
    });
    assert(made.status === 201, `MADE_TO_ORDER create failed ${JSON.stringify(made.json)}`);
    assert(made.json.catalogType === "REGULAR", "MADE_TO_ORDER remains REGULAR");
    assert(made.json.availabilityMode === "MADE_TO_ORDER", "availabilityMode stored");
    assert(made.json.preparationTimeMinutes === 240, "prep minutes stored");
    assert(made.json.maxDailyOrders === 1, "maxDailyOrders stored");
    listingIds.push(made.json.id);

    const secondLive = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Second cake ${stamp}`,
        price: 500,
        foodType: "VEG",
        category: "Desserts",
        quantity: 10,
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 60,
      },
    });
    assert(secondLive.status === 400, "second live MADE_TO_ORDER must be 400");
    assert(secondLive.json.code === "SINGLE_MADE_TO_ORDER", "single MTO code");

    const edited = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${made.json.id}`,
      token: sellerToken,
      body: {
        foodType: "VEG",
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 180,
        maxDailyOrders: 1,
      },
    });
    assert(edited.status === 200, `edit MADE_TO_ORDER failed ${JSON.stringify(edited.json)}`);
    assert(edited.json.preparationTimeMinutes === 180, "prep minutes updated");
    assert(edited.json.catalogType === "REGULAR", "edit does not change catalogType");

    const paused = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${made.json.id}/pause`,
      token: sellerToken,
    });
    assert(paused.status === 200, "pause MADE_TO_ORDER");

    const pausedOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
      },
    });
    assert(pausedOrder.status === 400, "paused MADE_TO_ORDER cannot be ordered");

    const resumed = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${made.json.id}/resume`,
      token: sellerToken,
    });
    assert(resumed.status === 200, "resume MADE_TO_ORDER");

    const mixedCart = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [
          { listingId: readyNow.json.id, quantity: 1 },
          { listingId: made.json.id, quantity: 1 },
        ],
      },
    });
    assert(mixedCart.status === 400, "mixed READY_NOW + MADE_TO_ORDER must be rejected");
    assert(
      String(mixedCart.json && mixedCart.json.error).includes("mix"),
      "mixed cart error should mention mix"
    );

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
    assert(cashOrder.status === 201, `COD MADE_TO_ORDER order failed ${JSON.stringify(cashOrder.json)}`);
    assert(cashOrder.json.status === "pending", "MTO orders start pending");
    orderIds.push(cashOrder.json.id);

    const rejected = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${cashOrder.json.id}/reject`,
      token: sellerToken,
      body: { reason: "Not available today" },
    });
    assert(rejected.status === 200, "seller can reject MADE_TO_ORDER request");
    assert(rejected.json.status === "rejected", "rejected status");

    const cashOrder2 = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
      },
    });
    assert(cashOrder2.status === 201, "COD order after reject");
    orderIds.push(cashOrder2.json.id);

    const accepted = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${cashOrder2.json.id}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });
    assert(accepted.status === 200, "seller can accept MADE_TO_ORDER request");
    assert(accepted.json.status === "accepted", "accepted status");

    const readyTime = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${cashOrder2.json.id}/ready-time`,
      token: sellerToken,
      body: { readyInMinutes: 45 },
    });
    assert(readyTime.status === 200, `COD ready-time failed ${JSON.stringify(readyTime.json)}`);

    const cashReady = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${cashOrder2.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(cashReady.status === 200, `COD MADE_TO_ORDER ready failed ${JSON.stringify(cashReady.json)}`);

    const blockedByCap = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: made.json.id, quantity: 1 }],
      },
    });
    assert(blockedByCap.status === 400, "maxDailyOrders must block further accepted-day orders");

    const raiseCap = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${made.json.id}`,
      token: sellerToken,
      body: {
        foodType: "VEG",
        availabilityMode: "MADE_TO_ORDER",
        preparationTimeMinutes: 180,
        maxDailyOrders: 20,
      },
    });
    assert(raiseCap.status === 200, "raise maxDailyOrders for UPI order");

    const upiOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "upi",
        items: [{ listingId: made.json.id, quantity: 1 }],
      },
    });
    assert(upiOrder.status === 201, `UPI MTO order failed ${JSON.stringify(upiOrder.json)}`);
    orderIds.push(upiOrder.json.id);

    const upiAccepted = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });
    assert(upiAccepted.status === 200, "UPI MTO accept");

    const readyTooSoon = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(readyTooSoon.status === 400, "UPI MTO cannot be marked ready before payment confirmation");
    assert(upiAccepted.json.status === "accepted", "unpaid UPI is not auto-cancelled");

    const stillOpen = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${upiOrder.json.id}`,
      token: buyerToken,
    });
    assert(
      stillOpen.status === 200 || stillOpen.status === 404,
      "GET order after blocked ready"
    );
    if (stillOpen.status === 200) {
      assert(stillOpen.json.status !== "cancelled", "no automatic cancellation for unpaid UPI");
    }

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
    assert(confirm.status === 200, `confirm+time failed ${JSON.stringify(confirm.json)}`);
    assert(confirm.json.expectedReadyAt, "seller chooses ready time after payment confirmation");

    const upiReady = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(upiReady.status === 200, "UPI MTO ready after confirmation");

    const marketplace = await jsonRequest(server, {
      method: "GET",
      path: `/listings?catalogType=REGULAR`,
      token: buyerToken,
    });
    assert(marketplace.status === 200, "regular marketplace still works");
    const marketplaceIds = (marketplace.json || []).map((row) => row.id);
    assert(marketplaceIds.includes(made.json.id), "MADE_TO_ORDER appears in regular marketplace");
    assert(!marketplaceIds.includes(preorderOk.json.id), "PREORDER stays out of regular marketplace");
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
    console.log("listing-availability tests passed");
    process.exit(0);
  })
  .catch(async (err) => {
    console.error(err);
    await prisma.$disconnect();
    process.exit(1);
  });
