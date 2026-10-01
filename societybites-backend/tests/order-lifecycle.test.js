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
    assert(happy.status === "accepted", "regular orders must skip seller acceptance");
    assert(happy.paymentStatus === "pending", "payment status must stay independent at create");
    assert(happy.statusStep === 1, "auto-accepted statusStep must be 1");
    assert(happy.sellerCanDecline === true, "seller keeps Can't fulfil after auto-accept");

    const reAccept = await patchStatus(server, {
      token: sellerToken,
      orderId: happy.id,
      status: "accepted",
    });
    assert(reAccept.status === 400, "ACCEPTED → ACCEPTED must be rejected");

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
    const missingReason = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${rejectOrder.id}/reject`,
      token: sellerToken,
      body: {},
    });
    assert(missingReason.status === 400, "reject without reason must fail");

    const rejected = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${rejectOrder.id}/reject`,
      token: sellerToken,
      body: { reason: "Ingredients unavailable", otherText: "Ran out of filling" },
    });
    assert(rejected.status === 200, "ACCEPTED → REJECTED must work");
    assert(rejected.json.status === "rejected", "rejected status not stored");
    assert(rejected.json.paymentStatus === "failed", "unpaid reject should fail payment");
    assert(
      rejected.json.rejectReason === "Ingredients unavailable\nRan out of filling",
      "reject reason must be stored"
    );
    assert(rejected.json.rejectedAt, "rejectedAt must be stored");

    const buyerRejected = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${rejectOrder.id}`,
      token: buyerToken,
    });
    assert(buyerRejected.status === 200, "buyer can load rejected order");
    assert(
      buyerRejected.json.rejectReason === "Ingredients unavailable\nRan out of filling",
      "buyer must receive reject reason"
    );

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
    const [firstReady, secondReady] = await Promise.all([
      patchStatus(server, {
        token: sellerToken,
        orderId: dupAcceptOrder.id,
        status: "ready",
      }),
      patchStatus(server, {
        token: sellerToken,
        orderId: dupAcceptOrder.id,
        status: "ready",
      }),
    ]);
    const readyCodes = [firstReady.status, secondReady.status].sort();
    assert(
      readyCodes[0] === 200 && readyCodes[1] !== 200,
      `duplicate ready must only succeed once, got ${readyCodes}`
    );
    const afterDupReady = await prisma.order.findUnique({
      where: { id: dupAcceptOrder.id },
    });
    assert(afterDupReady.status === "ready", "duplicate ready left an inconsistent status");

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
    assert(
      upiOrder.status === "accepted",
      "regular UPI orders must be payable straight after checkout"
    );
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
    assert(cancelled.status === 200, "cash buyer cancel before ready must still work");
    assert(cancelled.json.status === "cancelled", "cancel status not stored");

    const cantFulfil = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(cantFulfil.id);
    const declined = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${cantFulfil.id}/reject`,
      token: sellerToken,
      body: { reason: "Too many orders" },
    });
    assert(declined.status === 200, "Can't fulfil must work on an auto-accepted order");
    assert(declined.json.status === "rejected", "Can't fulfil must store rejected");

    const readyThenDecline = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(readyThenDecline.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: readyThenDecline.id,
      status: "ready",
    });
    const tooLateToDecline = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${readyThenDecline.id}/reject`,
      token: sellerToken,
      body: { reason: "Too many orders" },
    });
    assert(tooLateToDecline.status === 400, "Can't fulfil must close once the order is ready");

    const leftoverPreparing = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(leftoverPreparing.id);
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
