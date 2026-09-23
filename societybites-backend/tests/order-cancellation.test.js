require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");
const paymentRoutes = require("../routes/payments");
const { buyerCancelDeniedReason } = require("../lib/buyerCancel");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_BUYER_PHONE = "+919111000039";

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

assert(
  buyerCancelDeniedReason({
    paymentMethod: "upi",
    paymentStatus: "pending",
    status: "accepted",
  }) === null,
  "unit: unpaid accepted UPI is cancellable"
);
assert(
  buyerCancelDeniedReason({
    paymentMethod: "upi",
    paymentStatus: "buyer_marked_paid",
    status: "accepted",
  }) === "Order cannot be cancelled after payment has been marked as paid.",
  "unit: I've Paid blocks cancel"
);
assert(
  buyerCancelDeniedReason({
    paymentMethod: "cash",
    paymentStatus: "pending",
    status: "accepted",
  }) === "Order cannot be cancelled after the seller accepts the order.",
  "unit: COD accept blocks cancel"
);

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const otherBuyer = await prisma.user.upsert({
    where: { phone: OTHER_BUYER_PHONE },
    update: {
      name: "Cancel Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: OTHER_BUYER_PHONE,
      name: "Cancel Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
    },
  });

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);
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
        name: `Cancel ${Date.now()}`,
        price: 75,
        quantity: 30,
        status: "active",
      },
    });
    listingIds.push(listing.id);

    const upiPending = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "upi",
    });
    orderIds.push(upiPending.id);
    const upiPendingCancel = await patchStatus(server, {
      token: buyerToken,
      orderId: upiPending.id,
      status: "cancelled",
    });
    assert(upiPendingCancel.status === 200, "UPI pending unpaid must cancel");

    const upiAccepted = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "upi",
    });
    orderIds.push(upiAccepted.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: upiAccepted.id,
      status: "accepted",
    });
    const upiAcceptedCancel = await patchStatus(server, {
      token: buyerToken,
      orderId: upiAccepted.id,
      status: "cancelled",
    });
    assert(upiAcceptedCancel.status === 200, "UPI accepted unpaid must cancel");

    const upiMarked = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "upi",
    });
    orderIds.push(upiMarked.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: upiMarked.id,
      status: "accepted",
    });
    const marked = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiMarked.id}/mark-paid`,
      token: buyerToken,
      body: {},
    });
    assert(marked.status === 200, `mark-paid failed: ${JSON.stringify(marked.json)}`);
    const afterMarked = await patchStatus(server, {
      token: buyerToken,
      orderId: upiMarked.id,
      status: "cancelled",
    });
    assert(afterMarked.status === 400, "UPI buyer_marked_paid must not cancel");
    assert(
      afterMarked.json.error ===
        "Order cannot be cancelled after payment has been marked as paid.",
      `marked-paid cancel message: ${afterMarked.json.error}`
    );
    assert(marked.json.status === "accepted", "I've Paid must not change order status");

    const confirmedPay = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiMarked.id}/confirm`,
      token: sellerToken,
    });
    assert(confirmedPay.status === 200, "UPI confirm must still work");
    const afterConfirmed = await patchStatus(server, {
      token: buyerToken,
      orderId: upiMarked.id,
      status: "cancelled",
    });
    assert(afterConfirmed.status === 400, "UPI seller_confirmed must not cancel");

    const upiReady = await patchStatus(server, {
      token: sellerToken,
      orderId: upiMarked.id,
      status: "ready",
    });
    assert(upiReady.status === 200, "UPI ready after confirm must still work");
    const afterReady = await patchStatus(server, {
      token: buyerToken,
      orderId: upiMarked.id,
      status: "cancelled",
    });
    assert(afterReady.status === 400, "UPI ready must not cancel");

    const completed = await patchStatus(server, {
      token: sellerToken,
      orderId: upiMarked.id,
      status: "completed",
    });
    assert(completed.status === 200, "UPI complete must still work");
    const afterComplete = await patchStatus(server, {
      token: buyerToken,
      orderId: upiMarked.id,
      status: "cancelled",
    });
    assert(afterComplete.status === 400, "UPI completed must not cancel");

    const outsiderUpi = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "upi",
    });
    orderIds.push(outsiderUpi.id);
    const outsiderCancel = await patchStatus(server, {
      token: otherBuyerToken,
      orderId: outsiderUpi.id,
      status: "cancelled",
    });
    assert(outsiderCancel.status === 403, "non-buyer cannot cancel UPI order");

    const cashPending = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(cashPending.id);
    const cashPendingCancel = await patchStatus(server, {
      token: buyerToken,
      orderId: cashPending.id,
      status: "cancelled",
    });
    assert(cashPendingCancel.status === 200, "COD pending must cancel");

    const cashAccepted = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(cashAccepted.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: cashAccepted.id,
      status: "accepted",
    });
    const cashAcceptedCancel = await patchStatus(server, {
      token: buyerToken,
      orderId: cashAccepted.id,
      status: "cancelled",
    });
    assert(cashAcceptedCancel.status === 400, "COD accepted must not cancel");
    assert(
      cashAcceptedCancel.json.error ===
        "Order cannot be cancelled after the seller accepts the order.",
      `COD accept cancel message: ${cashAcceptedCancel.json.error}`
    );

    const cashReadyOrder = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(cashReadyOrder.id);
    await patchStatus(server, {
      token: sellerToken,
      orderId: cashReadyOrder.id,
      status: "accepted",
    });
    const cashReady = await patchStatus(server, {
      token: sellerToken,
      orderId: cashReadyOrder.id,
      status: "ready",
    });
    assert(cashReady.status === 200, "COD ready must still work");
    const cashReadyCancel = await patchStatus(server, {
      token: buyerToken,
      orderId: cashReadyOrder.id,
      status: "cancelled",
    });
    assert(cashReadyCancel.status === 400, "COD ready must not cancel");

    const cashPaid = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${cashReadyOrder.id}/confirm-cash`,
      token: sellerToken,
    });
    assert(cashPaid.status === 200, "COD cash confirm must still work");
    const cashComplete = await patchStatus(server, {
      token: sellerToken,
      orderId: cashReadyOrder.id,
      status: "completed",
    });
    assert(cashComplete.status === 200, "COD complete must still work");
    const cashCompleteCancel = await patchStatus(server, {
      token: buyerToken,
      orderId: cashReadyOrder.id,
      status: "cancelled",
    });
    assert(cashCompleteCancel.status === 400, "COD completed must not cancel");

    const outsiderCod = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(outsiderCod.id);
    const outsiderCodCancel = await patchStatus(server, {
      token: otherBuyerToken,
      orderId: outsiderCod.id,
      status: "cancelled",
    });
    assert(outsiderCodCancel.status === 403, "non-buyer cannot cancel COD order");

    const byNumber = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "upi",
    });
    orderIds.push(byNumber.id);
    const cancelByNumber = await patchStatus(server, {
      token: buyerToken,
      orderId: byNumber.orderNumber,
      status: "cancelled",
    });
    assert(
      cancelByNumber.status === 200,
      `cancel by orderNumber failed: ${cancelByNumber.status} ${JSON.stringify(cancelByNumber.json)}`
    );

    console.log("order-cancellation.test.js: all assertions passed");
  } finally {
    await new Promise((resolve, reject) =>
      server.close((err) => (err ? reject(err) : resolve()))
    );
    if (orderIds.length) {
      await prisma.message.deleteMany({ where: { orderId: { in: orderIds } } }).catch(() => {});
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    await prisma.user.deleteMany({ where: { phone: OTHER_BUYER_PHONE } });
    await prisma.$disconnect();
  }
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect().catch(() => {});
  process.exit(1);
});
