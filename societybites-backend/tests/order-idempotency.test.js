require("dotenv").config();
const http = require("http");
const express = require("express");
const { randomUUID } = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_BUYER_PHONE = "+919111000029";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body, headers = {} }) {
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
          ...headers,
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

function placeOrder(server, { token, listingId, quantity = 1, idempotencyKey }) {
  const headers = idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {};
  return jsonRequest(server, {
    method: "POST",
    path: "/orders",
    token,
    body: {
      paymentMethod: "upi",
      items: [{ listingId, quantity }],
    },
    headers,
  });
}

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const otherBuyer = await prisma.user.upsert({
    where: { phone: OTHER_BUYER_PHONE },
    update: {
      name: "Idempotency Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: OTHER_BUYER_PHONE,
      name: "Idempotency Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
    },
  });

  const buyerToken = signToken(buyer);
  const otherBuyerToken = signToken(otherBuyer);

  const app = express();
  app.use(express.json());
  app.use("/orders", orderRoutes);
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

  try {
    const listing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Idempotency ${Date.now()}`,
        price: 50,
        quantity: 10,
        status: "active",
      },
    });
    listingIds.push(listing.id);

    const normalKey = `idem-normal-${randomUUID()}`;
    const first = await placeOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      idempotencyKey: normalKey,
    });
    assert(first.status === 201, `normal order: ${first.status} ${JSON.stringify(first.json)}`);
    const orderId = first.json.id;

    const afterStock = await prisma.listing.findUnique({ where: { id: listing.id } });
    assert(afterStock.quantity === 9, "stock decremented once");

    const sharedKey = `idem-shared-${randomUUID()}`;
    const stockListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Idempotency stock ${Date.now()}`,
        price: 40,
        quantity: 1,
        status: "active",
      },
    });
    listingIds.push(stockListing.id);

    const dup1 = await placeOrder(server, {
      token: buyerToken,
      listingId: stockListing.id,
      idempotencyKey: sharedKey,
    });
    assert(dup1.status === 201, `first shared-key order: ${dup1.status}`);

    const dup2 = await placeOrder(server, {
      token: buyerToken,
      listingId: stockListing.id,
      idempotencyKey: sharedKey,
    });
    assert(dup2.status === 201, `replay must be 201: ${dup2.status}`);
    assert(dup2.json.id === dup1.json.id, "same key must return same order id");
    assert(
      dup2.json.orderNumber === dup1.json.orderNumber,
      "same key must return same order number"
    );

    const stockAfterDup = await prisma.listing.findUnique({
      where: { id: stockListing.id },
    });
    assert(stockAfterDup.quantity === 0, "stock must not be reserved twice for same key");

    const orderCountDup = await prisma.order.count({
      where: { buyerId: buyer.id, items: { some: { listingId: stockListing.id } } },
    });
    assert(orderCountDup === 1, "only one order row for duplicate key submissions");

    const concurrentKey = `idem-concurrent-${randomUUID()}`;
    const concurrentListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Idempotency concurrent ${Date.now()}`,
        price: 30,
        quantity: 1,
        status: "active",
      },
    });
    listingIds.push(concurrentListing.id);

    const [c1, c2] = await Promise.all([
      placeOrder(server, {
        token: buyerToken,
        listingId: concurrentListing.id,
        idempotencyKey: concurrentKey,
      }),
      placeOrder(server, {
        token: buyerToken,
        listingId: concurrentListing.id,
        idempotencyKey: concurrentKey,
      }),
    ]);
    assert(c1.status === 201 && c2.status === 201, "concurrent requests must succeed");
    assert(c1.json.id === c2.json.id, "concurrent duplicate must share one order");

    const concurrentStock = await prisma.listing.findUnique({
      where: { id: concurrentListing.id },
    });
    assert(concurrentStock.quantity === 0, "concurrent idempotent request reserves stock once");

    const crossBuyerKey = `idem-cross-${randomUUID()}`;
    const crossListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Idempotency cross buyer ${Date.now()}`,
        price: 25,
        quantity: 5,
        status: "active",
      },
    });
    listingIds.push(crossListing.id);

    const buyerA = await placeOrder(server, {
      token: buyerToken,
      listingId: crossListing.id,
      idempotencyKey: crossBuyerKey,
    });
    assert(buyerA.status === 201, "buyer A order");

    const buyerB = await placeOrder(server, {
      token: otherBuyerToken,
      listingId: crossListing.id,
      idempotencyKey: crossBuyerKey,
    });
    assert(buyerB.status === 201, "buyer B order with same key string");
    assert(buyerB.json.id !== buyerA.json.id, "different buyers must not share orders");

    const newKeyListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Idempotency new key ${Date.now()}`,
        price: 20,
        quantity: 3,
        status: "active",
      },
    });
    listingIds.push(newKeyListing.id);

    const keyA = `idem-new-a-${randomUUID()}`;
    const keyB = `idem-new-b-${randomUUID()}`;
    const oA = await placeOrder(server, {
      token: buyerToken,
      listingId: newKeyListing.id,
      idempotencyKey: keyA,
    });
    const oB = await placeOrder(server, {
      token: buyerToken,
      listingId: newKeyListing.id,
      idempotencyKey: keyB,
    });
    assert(oA.status === 201 && oB.status === 201, "new keys create orders");
    assert(oA.json.id !== oB.json.id, "different keys must create different orders");

    const failKey = `idem-fail-${randomUUID()}`;
    const failListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Idempotency fail ${Date.now()}`,
        price: 15,
        quantity: 2,
        status: "active",
      },
    });
    listingIds.push(failListing.id);

    const badQty = await placeOrder(server, {
      token: buyerToken,
      listingId: failListing.id,
      quantity: 99,
      idempotencyKey: failKey,
    });
    assert(badQty.status === 409, `oversell must fail: ${badQty.status}`);

    const retryOk = await placeOrder(server, {
      token: buyerToken,
      listingId: failListing.id,
      quantity: 1,
      idempotencyKey: failKey,
    });
    assert(retryOk.status === 201, `retry after failed txn must succeed: ${retryOk.status}`);

    const failStock = await prisma.listing.findUnique({ where: { id: failListing.id } });
    assert(failStock.quantity === 1, "failed attempt must not reserve stock");

    const idemRows = await prisma.orderIdempotency.count({
      where: { buyerId: buyer.id, orderId },
    });
    assert(idemRows === 1, "completed idempotency row exists for normal order");

    console.log("order-idempotency.test.js: all assertions passed");
  } finally {
    server.close();
    if (listingIds.length) {
      await prisma.orderItem.deleteMany({ where: { listingId: { in: listingIds } } });
      await prisma.order.deleteMany({
        where: { items: { some: { listingId: { in: listingIds } } } },
      });
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    await prisma.orderIdempotency.deleteMany({
      where: {
        buyerId: { in: [buyer.id, otherBuyer.id] },
        idempotencyKey: { contains: "idem-" },
      },
    });
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
