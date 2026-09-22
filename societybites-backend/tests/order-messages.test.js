require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_SELLER_PHONE = "+919111000028";
const OTHER_BUYER_PHONE = "+919111000029";

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

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const otherSeller = await prisma.user.upsert({
    where: { phone: OTHER_SELLER_PHONE },
    update: {
      name: "Messages Other Seller",
      role: "seller",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: OTHER_SELLER_PHONE,
      name: "Messages Other Seller",
      role: "seller",
      societyId: seller.societyId,
    },
  });

  const otherBuyer = await prisma.user.upsert({
    where: { phone: OTHER_BUYER_PHONE },
    update: {
      name: "Messages Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: OTHER_BUYER_PHONE,
      name: "Messages Other Buyer",
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
        name: `Messages ${Date.now()}`,
        price: 70,
        quantity: 10,
        status: "active",
      },
    });
    listingIds.push(listing.id);

    const created = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(created.status === 201, `order create failed: ${created.status}`);
    orderIds.push(created.json.id);
    assert(created.json.status === "pending", "existing order create must stay pending");
    assert(
      created.json.unreadMessageCount == null,
      "create order payload must stay unchanged (no unread field required)"
    );

    const getFresh = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}`,
      token: buyerToken,
    });
    assert(getFresh.status === 200, "GET order without messages must work");
    assert(getFresh.json.status === "pending", "GET must not change status");
    assert(
      getFresh.json.unreadMessageCount === 0,
      "orders without messages report zero unread"
    );

    const emptyGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}/messages`,
      token: buyerToken,
    });
    assert(emptyGet.status === 200, "buyer must retrieve own empty thread");
    assert(Array.isArray(emptyGet.json) && emptyGet.json.length === 0, "empty thread");

    const sellerEmpty = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}/messages`,
      token: sellerToken,
    });
    assert(sellerEmpty.status === 200, "seller must retrieve own empty thread");

    const buyerSend = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${created.json.id}/messages`,
      token: buyerToken,
      body: { message: "  Can I collect this around 6 PM?  " },
    });
    assert(buyerSend.status === 201, `buyer send failed: ${buyerSend.status}`);
    assert(buyerSend.json.message === "Can I collect this around 6 PM?", "trim whitespace");
    assert(buyerSend.json.senderRole === "buyer", "buyer senderRole");
    assert(buyerSend.json.senderId === buyer.id, "sender from auth user");

    const sellerList = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller",
      token: sellerToken,
    });
    assert(sellerList.status === 200, "seller order list must still work");
    const listed = sellerList.json.find((row) => row.id === created.json.id);
    assert(listed, "order must remain on seller list without messages breaking it");
    assert(listed.unreadMessageCount >= 1, "seller should see unread from buyer");

    const sellerGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}/messages`,
      token: sellerToken,
    });
    assert(sellerGet.status === 200, "seller retrieve after buyer send");
    assert(sellerGet.json.length === 1, "one message");
    assert(sellerGet.json[0].message === "Can I collect this around 6 PM?");

    const sellerAfterRead = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}`,
      token: sellerToken,
    });
    assert(sellerAfterRead.status === 200, "existing GET order must work");
    assert(
      sellerAfterRead.json.unreadMessageCount === 0,
      "opening conversation marks inbound unread as read"
    );
    assert(sellerAfterRead.json.status === "pending", "messaging must not change status");

    const sellerSend = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${created.json.id}/messages`,
      token: sellerToken,
      body: { message: "Yes, that works." },
    });
    assert(sellerSend.status === 201, "seller can send");
    assert(sellerSend.json.senderRole === "seller", "seller senderRole");

    const buyerThread = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}/messages`,
      token: buyerToken,
    });
    assert(buyerThread.status === 200, "buyer retrieve after both sends");
    assert(buyerThread.json.length === 2, "chronological pair");
    assert(buyerThread.json[0].createdAt <= buyerThread.json[1].createdAt, "oldest first");
    assert(buyerThread.json[0].senderRole === "buyer");
    assert(buyerThread.json[1].senderRole === "seller");

    const emptyMsg = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${created.json.id}/messages`,
      token: buyerToken,
      body: { message: "   " },
    });
    assert(emptyMsg.status === 400, "whitespace-only message rejected");

    const missing = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${created.json.id}/messages`,
      token: buyerToken,
      body: {},
    });
    assert(missing.status === 400, "missing message rejected");

    const tooLong = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${created.json.id}/messages`,
      token: buyerToken,
      body: { message: "x".repeat(501) },
    });
    assert(tooLong.status === 400, "message over 500 characters rejected");

    const otherBuyerGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}/messages`,
      token: otherBuyerToken,
    });
    assert(otherBuyerGet.status === 403, "other buyer cannot read messages");

    const otherSellerGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${created.json.id}/messages`,
      token: otherSellerToken,
    });
    assert(otherSellerGet.status === 403, "other seller cannot read messages");

    const otherBuyerSend = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${created.json.id}/messages`,
      token: otherBuyerToken,
      body: { message: "Hi" },
    });
    assert(otherBuyerSend.status === 403, "outsider cannot send");

    const missingOrder = await jsonRequest(server, {
      method: "GET",
      path: "/orders/00000000-0000-0000-0000-000000000000/messages",
      token: buyerToken,
    });
    assert(missingOrder.status === 404, "unknown order is 404");

    console.log("order-messages.test.js: all assertions passed");
  } finally {
    await new Promise((resolve, reject) => server.close((err) => (err ? reject(err) : resolve())));
    if (orderIds.length) {
      await prisma.message.deleteMany({ where: { orderId: { in: orderIds } } });
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    await prisma.user.deleteMany({
      where: { phone: { in: [OTHER_SELLER_PHONE, OTHER_BUYER_PHONE] } },
    });
    await prisma.$disconnect();
  }
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect().catch(() => {});
  process.exit(1);
});
