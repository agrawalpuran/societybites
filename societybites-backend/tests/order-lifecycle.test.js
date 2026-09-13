require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");
const paymentRoutes = require("../routes/payments");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_SELLER_PHONE = "+919111000018";
const OTHER_BUYER_PHONE = "+919111000019";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const request = http.request(
      {
        hostname: "127.0.0.1",
        port: address.port,
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
      (response) => {
        let data = "";
        response.on("data", (chunk) => (data += chunk));
        response.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {}
          resolve({ status: response.statusCode, json });
        });
      }
    );
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

async function createOrder(server, { token, listingId, paymentMethod }) {
  const created = await jsonRequest(server, {
    method: "POST",
    path: "/orders",
    token,
    body: {
      paymentMethod,
      items: [{ listingId, quantity: 1 }],
    },
  });
  assert(
    created.status === 201,
    `order create failed: ${created.status} ${JSON.stringify(created.json)}`
  );
  return created.json;
}

async function patchStatus(server, { token, orderId, status }) {
  return jsonRequest(server, {
    method: "PATCH",
    path: `/orders/${orderId}/status`,
    token,
    body: { status },
  });
}

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const otherSeller = await prisma.user.upsert({
    where: { phone: OTHER_SELLER_PHONE },
    update: {
      name: "Lifecycle Other Seller",
      role: "seller",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: OTHER_SELLER_PHONE,
      name: "Lifecycle Other Seller",
      role: "seller",
      societyId: seller.societyId,
    },
  });

  const otherBuyer = await prisma.user.upsert({
    where: { phone: OTHER_BUYER_PHONE },
    update: {
      name: "Lifecycle Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: OTHER_BUYER_PHONE,
      name: "Lifecycle Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
    },
  });

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);
  const otherSellerToken = signToken(otherSeller);
  const otherBuyerToken = signToken(otherBuyer);

  const app = express();
  app.use(express.json());
  app.use("/orders", orderRoutes);
  app.use("/payments", paymentRoutes);
  app.use((error, _req, res, _next) => {
    const statusCode = error.statusCode || 500;
    res
      .status(statusCode)
      .json({ error: statusCode === 500 ? "Internal server error" : error.message });
  });

  const server = await new Promise((resolve) => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
  });

  const listingIds = [];
  const orderIds = [];

  try {
    const listing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Lifecycle ${Date.now()}`,
        price: 80,
        quantity: 20,
        status: "active",
      },
    });
    listingIds.push(listing.id);

    const happy = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(happy.id);
    assert(happy.status === "pending", "new orders must start pending");
    assert(happy.paymentStatus === "pending", "payment status must stay independent at create");
    assert(happy.statusStep === 0, "pending statusStep must be 0");

    const accepted = await patchStatus(server, {
      token: sellerToken,
      orderId: happy.id,
      status: "accepted",
    });
    assert(accepted.status === 200, "PENDING → ACCEPTED must work");
    assert(accepted.json.status === "accepted", "accepted status not stored");
    assert(accepted.json.paymentStatus === "pending", "accept must not change paymentStatus");
    assert(accepted.json.statusStep === 1, "accepted statusStep must be 1");

    const ready = await patchStatus(server, {
      token: sellerToken,
      orderId: happy.id,
      status: "ready",
    });
    assert(ready.status === 200, "ACCEPTED → READY must work");
    assert(ready.json.status === "ready", "ready status not stored");
    assert(ready.json.paymentStatus === "pending", "ready must not change paymentStatus");
    assert(ready.json.statusStep === 2, "ready statusStep must be 2");

    const cashTooSoon = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${happy.id}/confirm-cash`,
      token: sellerToken,
    });
    assert(cashTooSoon.status === 200, "cash confirm at READY must work");
    assert(cashTooSoon.json.status === "ready", "cash confirm must not change order status");
    assert(cashTooSoon.json.paymentStatus === "paid", "cash confirm must set payment paid");

    const completed = await patchStatus(server, {
      token: sellerToken,
      orderId: happy.id,
      status: "completed",
    });
    assert(completed.status === 200, "READY → COMPLETED must work");
    assert(completed.json.status === "completed", "completed status not stored");
    assert(completed.json.paymentStatus === "paid", "complete must not rewrite cash paymentStatus");
    assert(completed.json.statusStep === 3, "completed statusStep must be 3");

    const afterComplete = await patchStatus(server, {
      token: sellerToken,
      orderId: happy.id,
      status: "accepted",
    });
    assert(afterComplete.status === 400, "COMPLETED cannot transition further");

    const rejectOrder = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(rejectOrder.id);
    const rejected = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${rejectOrder.id}/reject`,
      token: sellerToken,
      body: {},
    });
    assert(rejected.status === 200, "PENDING → REJECTED must work");
    assert(rejected.json.status === "rejected", "rejected status not stored");
    assert(rejected.json.paymentStatus === "failed", "unpaid reject should fail payment");

    const rejectThenAccept = await patchStatus(server, {
      token: sellerToken,
      orderId: rejectOrder.id,
      status: "accepted",
    });
    assert(rejectThenAccept.status === 400, "REJECTED → ACCEPTED must be rejected");

    const rejectThenReady = await patchStatus(server, {
      token: sellerToken,
      orderId: rejectOrder.id,
      status: "ready",
    });
    assert(rejectThenReady.status === 400, "REJECTED → READY must be rejected");

    const invalids = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(invalids.id);

    const pendingReady = await patchStatus(server, {
      token: sellerToken,
      orderId: invalids.id,
      status: "ready",
    });
    assert(pendingReady.status === 400, "PENDING → READY must be rejected");

    const pendingCompleted = await patchStatus(server, {
      token: sellerToken,
      orderId: invalids.id,
      status: "completed",
    });
    assert(pendingCompleted.status === 400, "PENDING → COMPLETED must be rejected");

    const acceptForSkip = await patchStatus(server, {
      token: sellerToken,
      orderId: invalids.id,
      status: "accepted",
    });
    assert(acceptForSkip.status === 200, "setup accept for skip-complete failed");

    const acceptedCompleted = await patchStatus(server, {
      token: sellerToken,
      orderId: invalids.id,
      status: "completed",
    });
    assert(acceptedCompleted.status === 400, "ACCEPTED → COMPLETED must be rejected");

    const assignPreparing = await patchStatus(server, {
      token: sellerToken,
      orderId: invalids.id,
      status: "preparing",
    });
    assert(assignPreparing.status === 400, "PREPARING cannot be assigned to new orders");

    const assignPickup = await patchStatus(server, {
      token: sellerToken,
      orderId: invalids.id,
      status: "picked_up",
    });
    assert(assignPickup.status === 400, "PICKUP cannot be assigned to new orders");

    const unauthorized = await patchStatus(server, {
      token: otherSellerToken,
      orderId: invalids.id,
      status: "ready",
    });
    assert(unauthorized.status === 403, "unauthorized seller cannot modify another seller's order");

    const buyerReady = await patchStatus(server, {
      token: buyerToken,
      orderId: invalids.id,
      status: "ready",
    });
    assert(buyerReady.status === 403, "buyer cannot perform seller status transitions");

    const buyerComplete = await patchStatus(server, {
      token: buyerToken,
      orderId: invalids.id,
      status: "completed",
    });
    assert(buyerComplete.status === 403, "buyer cannot complete an order");

    const otherBuyerPatch = await patchStatus(server, {
      token: otherBuyerToken,
      orderId: invalids.id,
      status: "cancelled",
    });
    assert(otherBuyerPatch.status === 403, "another buyer cannot cancel this order");

    const dupAcceptOrder = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(dupAcceptOrder.id);
    const [firstAccept, secondAccept] = await Promise.all([
      patchStatus(server, {
        token: sellerToken,
        orderId: dupAcceptOrder.id,
        status: "accepted",
      }),
      patchStatus(server, {
        token: sellerToken,
        orderId: dupAcceptOrder.id,
        status: "accepted",
      }),
    ]);
    const acceptCodes = [firstAccept.status, secondAccept.status].sort();
    assert(
      acceptCodes[0] === 200 && acceptCodes[1] !== 200,
      `duplicate accept must only succeed once, got ${acceptCodes}`
    );
    const afterDupAccept = await prisma.order.findUnique({
      where: { id: dupAcceptOrder.id },
    });
    assert(afterDupAccept.status === "accepted", "duplicate accept left an inconsistent status");

    await patchStatus(server, {
      token: sellerToken,
      orderId: dupAcceptOrder.id,
      status: "ready",
    });
    const cashDup = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${dupAcceptOrder.id}/confirm-cash`,
      token: sellerToken,
    });
    assert(cashDup.status === 200, "cash confirm before duplicate complete failed");
    const [firstComplete, secondComplete] = await Promise.all([
      patchStatus(server, {
        token: sellerToken,
        orderId: dupAcceptOrder.id,
        status: "completed",
      }),
      patchStatus(server, {
        token: sellerToken,
        orderId: dupAcceptOrder.id,
        status: "completed",
      }),
    ]);
    const completeCodes = [firstComplete.status, secondComplete.status].sort();
    assert(
      completeCodes[0] === 200 && completeCodes[1] !== 200,
      `duplicate complete must only succeed once, got ${completeCodes}`
    );

    const upiOrder = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "upi",
    });
    orderIds.push(upiOrder.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: upiOrder.id,
      status: "accepted",
    });
    const marked = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiOrder.id}/mark-paid`,
      token: buyerToken,
      body: {},
    });
    assert(marked.status === 200, `UPI mark-paid failed: ${JSON.stringify(marked.json)}`);
    assert(marked.json.status === "accepted", "mark-paid must not change order status");
    assert(marked.json.paymentStatus === "buyer_marked_paid", "mark-paid paymentStatus mismatch");

    const confirmed = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiOrder.id}/confirm`,
      token: sellerToken,
    });
    assert(confirmed.status === 200, `UPI confirm failed: ${JSON.stringify(confirmed.json)}`);
    assert(confirmed.json.status === "accepted", "payment confirm must not set preparing");
    assert(confirmed.json.status === marked.json.status, "UPI confirm must not change Order.status");
    assert(
      confirmed.json.timeline == null || confirmed.json.timeline.preparingAt == null,
      "UPI confirm must not set preparingAt"
    );
    assert(confirmed.json.paymentStatus === "seller_confirmed", "confirm paymentStatus mismatch");

    const upiReady = await patchStatus(server, {
      token: sellerToken,
      orderId: upiOrder.id,
      status: "ready",
    });
    assert(upiReady.status === 200, "UPI order ACCEPTED → READY failed");
    assert(upiReady.json.paymentStatus === "seller_confirmed", "ready must leave paymentStatus alone");

    const cancelOrder = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(cancelOrder.id);
    const cancelled = await patchStatus(server, {
      token: buyerToken,
      orderId: cancelOrder.id,
      status: "cancelled",
    });
    assert(cancelled.status === 200, "existing buyer cancel from pending must still work");
    assert(cancelled.json.status === "cancelled", "cancel status not stored");

    const rejectAccepted = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(rejectAccepted.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: rejectAccepted.id,
      status: "accepted",
    });
    const lateReject = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${rejectAccepted.id}/reject`,
      token: sellerToken,
      body: {},
    });
    assert(lateReject.status === 400, "reject after accept must not be allowed");

    const leftoverPreparing = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(leftoverPreparing.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: leftoverPreparing.id,
      status: "accepted",
    });
    await prisma.order.update({
      where: { id: leftoverPreparing.id },
      data: { status: "preparing", preparingAt: new Date() },
    });
    const leftoverReady = await patchStatus(server, {
      token: sellerToken,
      orderId: leftoverPreparing.id,
      status: "ready",
    });
    assert(
      leftoverReady.status === 200,
      `legacy preparing → ready must work: ${leftoverReady.status} ${JSON.stringify(leftoverReady.json)}`
    );
    assert(leftoverReady.json.status === "ready", "legacy preparing was not marked ready");

    console.log("order lifecycle tests: all passed");
  } finally {
    if (orderIds.length) {
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    await prisma.user.deleteMany({
      where: { phone: { in: [OTHER_SELLER_PHONE, OTHER_BUYER_PHONE] } },
    });
    server.close();
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
