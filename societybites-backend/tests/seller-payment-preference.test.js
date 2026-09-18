require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const {
  DEFAULT_PAYMENT_PREFERENCE,
  allowsCod,
  assertPaymentMethodAllowed,
  upiBlocksPreparation,
} = require("../lib/sellerPaymentPreference");
const authRoutes = require("../routes/auth");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");
const paymentRoutes = require("../routes/payments");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";

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
  assert(allowsCod("UPI_AND_COD"), "default preference allows COD");
  assert(!allowsCod("UPI_ONLY"), "UPI_ONLY hides COD");
  assertPaymentMethodAllowed({ preference: "UPI_ONLY", paymentMethod: "upi" });
  try {
    assertPaymentMethodAllowed({ preference: "UPI_ONLY", paymentMethod: "cash" });
    throw new Error("expected COD reject");
  } catch (err) {
    if (err.message === "expected COD reject") throw err;
    assert(err.statusCode === 400, "COD reject is 400");
  }
  assert(
    upiBlocksPreparation({ paymentMethod: "upi", paymentStatus: "pending" }),
    "UPI pending blocks prep"
  );
  assert(
    upiBlocksPreparation({ paymentMethod: "upi", paymentStatus: "buyer_marked_paid" }),
    "buyer marked paid is not confirmation"
  );
  assert(
    !upiBlocksPreparation({ paymentMethod: "upi", paymentStatus: "seller_confirmed" }),
    "seller_confirmed unblocks"
  );
  assert(
    !upiBlocksPreparation({ paymentMethod: "cash", paymentStatus: "pending" }),
    "COD is not gated"
  );

  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  assert(seller && buyer, "seed seller and buyer required");

  const originalPreference = seller.paymentPreference || DEFAULT_PAYMENT_PREFERENCE;

  const reachBuyer = await prisma.user.create({
    data: {
      phone: `+9198${String(Date.now()).slice(-8)}`,
      role: "buyer",
      societyId: buyer.societyId,
    },
  });
  const reachBuyerToken = signToken(reachBuyer);
  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  app.use("/payments", paymentRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
    });
  });

  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  const listingIds = [];
  const orderIds = [];

  try {
    const me = await jsonRequest(server, { method: "GET", path: "/auth/me", token: sellerToken });
    assert(me.status === 200, "GET /me failed");
    assert(
      me.json.paymentPreference === originalPreference ||
        me.json.paymentPreference === DEFAULT_PAYMENT_PREFERENCE,
      "paymentPreference present on /me"
    );

    const buyerPatch = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: reachBuyerToken,
      body: { paymentPreference: "UPI_ONLY" },
    });
    assert(buyerPatch.status === 400, `buyers cannot change paymentPreference got ${buyerPatch.status} ${JSON.stringify(buyerPatch.json)}`);

    const setBoth = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { paymentPreference: "UPI_AND_COD" },
    });
    assert(setBoth.status === 200, "seller can set UPI_AND_COD");
    assert(setBoth.json.user.paymentPreference === "UPI_AND_COD", "UPI_AND_COD persisted");

    const listing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `PayPref ${Date.now()}`,
        price: 90,
        quantity: 20,
        status: "active",
      },
    });
    listingIds.push(listing.id);

    const cashOk = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(cashOk.status === 201, `COD allowed for UPI_AND_COD: ${JSON.stringify(cashOk.json)}`);
    orderIds.push(cashOk.json.id);
    assert(cashOk.json.paymentMethod === "cash", "COD snapshot");
    const cashFulfilment = cashOk.json.fulfilmentMethod;
    const cashCharge = cashOk.json.deliveryCharge;

    const setUpiOnly = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { paymentPreference: "UPI_ONLY" },
    });
    assert(setUpiOnly.status === 200, "seller can set UPI_ONLY");
    assert(setUpiOnly.json.user.paymentPreference === "UPI_ONLY", "UPI_ONLY persisted");

    const stale = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${cashOk.json.id}`,
      token: sellerToken,
    });
    assert(stale.json.paymentMethod === "cash", "existing order stays COD after profile change");
    assert(stale.json.fulfilmentMethod === cashFulfilment, "fulfilment snapshot unchanged");
    assert(stale.json.deliveryCharge === cashCharge, "delivery charge snapshot unchanged");

    const cashRejected = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(cashRejected.status === 400, "COD rejected for UPI_ONLY seller");
    assert(
      String(cashRejected.json && cashRejected.json.error).toLowerCase().includes("upi"),
      "COD reject message mentions UPI"
    );

    const upiOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(upiOrder.status === 201, `UPI checkout failed: ${JSON.stringify(upiOrder.json)}`);
    orderIds.push(upiOrder.json.id);
    assert(upiOrder.json.paymentMethod === "upi", "UPI snapshot");
    assert(upiOrder.json.paymentStatus === "pending", "UPI starts payment pending");

    await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });

    const readyTooSoon = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(readyTooSoon.status === 400, "UPI pending cannot mark ready");

    const timeTooSoon = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/ready-time`,
      token: sellerToken,
      body: { readyInMinutes: 15 },
    });
    assert(timeTooSoon.status === 400, "UPI pending cannot set ready-by");

    const markPaid = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiOrder.json.id}/mark-paid`,
      token: buyerToken,
      body: {},
    });
    assert(markPaid.status === 200, `I Have Paid failed: ${JSON.stringify(markPaid.json)}`);
    assert(markPaid.json.paymentStatus === "buyer_marked_paid", "mark-paid status");
    assert(markPaid.json.status === "accepted", "I Have Paid does not change order status");

    const readyAfterMark = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(readyAfterMark.status === 400, "buyer_marked_paid still blocks ready");

    const confirmWithTime = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiOrder.json.id}/confirm`,
      token: sellerToken,
      body: { readyInMinutes: 20 },
    });
    assert(confirmWithTime.status === 200, `confirm+time failed: ${JSON.stringify(confirmWithTime.json)}`);
    assert(confirmWithTime.json.paymentStatus === "seller_confirmed", "payment confirmed");
    assert(confirmWithTime.json.status === "accepted", "confirm does not change order status");
    assert(confirmWithTime.json.expectedReadyAt, "time snapshot on confirm");

    const readyAfterConfirm = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${upiOrder.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(readyAfterConfirm.status === 200, "UPI ready after payment confirmed");
    assert(readyAfterConfirm.json.paymentStatus === "seller_confirmed", "ready leaves paymentStatus");

    await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { paymentPreference: "UPI_AND_COD" },
    });

    const laterUpi = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${upiOrder.json.id}`,
      token: buyerToken,
    });
    assert(laterUpi.json.paymentMethod === "upi", "UPI order stays UPI after seller allows COD");

    const cashFlow = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(cashFlow.status === 201, "COD checkout after restoring UPI_AND_COD");
    orderIds.push(cashFlow.json.id);

    await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${cashFlow.json.id}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });
    const cashTime = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${cashFlow.json.id}/ready-time`,
      token: sellerToken,
      body: { readyInMinutes: 15 },
    });
    assert(cashTime.status === 200, `COD ready-by unchanged: ${JSON.stringify(cashTime.json)}`);
    const cashReady = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${cashFlow.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(cashReady.status === 200, "COD can mark ready without I Have Paid");

    const preorderListing = await prisma.listing.findFirst({
      where: {
        sellerId: seller.id,
        campaignId: { not: null },
        status: "active",
      },
    });
    if (preorderListing) {
      const preUpi = await jsonRequest(server, {
        method: "POST",
        path: "/orders",
        token: buyerToken,
        body: {
          type: "pre_order",
          campaignId: preorderListing.campaignId,
          paymentMethod: "upi",
          fulfilmentMethod: "pickup",
          items: [{ listingId: preorderListing.id, quantity: 1 }],
        },
      });
      if (preUpi.status === 201) {
        orderIds.push(preUpi.json.id);
        assert(preUpi.json.type === "pre_order", "preorder type unchanged");
        assert(preUpi.json.paymentMethod === "upi", "preorder UPI snapshot");
      } else {
        assert(
          preUpi.status === 400 || preUpi.status === 409,
          `preorder create unexpected ${preUpi.status} ${JSON.stringify(preUpi.json)}`
        );
      }
    }

    console.log("seller-payment-preference tests passed");
  } finally {
    await prisma.user.update({
      where: { id: seller.id },
      data: { paymentPreference: originalPreference },
    });
    await prisma.user.delete({ where: { id: reachBuyer.id } }).catch(() => {});
    if (orderIds.length) {
      await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } }).catch(() => {});
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } }).catch(() => {});
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } }).catch(() => {});
    }
    server.close();
    await prisma.$disconnect();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
