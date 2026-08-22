require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_BUYER_PHONE = "+919111000003";

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
          resolve({
            status: response.statusCode,
            json: data ? JSON.parse(data) : null,
          });
        });
      }
    );
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

async function assertDuration(server, sellerToken, orderId, minutes) {
  const before = Date.now();
  const response = await jsonRequest(server, {
    method: "PATCH",
    path: `/orders/${orderId}/ready-time`,
    token: sellerToken,
    body: { readyInMinutes: minutes },
  });
  const after = Date.now();

  assert(response.status === 200, `${minutes}-minute ready time failed`);
  const stored = new Date(response.json.expectedReadyAt).getTime();
  assert(
    stored >= before + minutes * 60 * 1000 &&
      stored <= after + minutes * 60 * 1000 + 1000,
    `${minutes}-minute ready time was not calculated from server current time`
  );
}

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const otherBuyer = await prisma.user.upsert({
    where: { phone: OTHER_BUYER_PHONE },
    update: {
      name: "Order Reconciliation Other Buyer",
      role: "buyer",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: OTHER_BUYER_PHONE,
      name: "Order Reconciliation Other Buyer",
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
  app.use((error, _req, res, _next) => {
    const statusCode = error.statusCode || 500;
    res
      .status(statusCode)
      .json({ error: statusCode === 500 ? "Internal server error" : error.message });
  });

  const server = await new Promise((resolve) => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
  });

  let listing;
  let orderId;
  try {
    listing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Order reconciliation ${Date.now()}`,
        price: 75,
        quantity: 2,
        status: "active",
      },
    });

    const created = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(created.status === 201, "test order creation failed");
    orderId = created.json.id;

    const accepted = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${orderId}/status`,
      token: sellerToken,
      body: { status: "accepted" },
    });
    assert(accepted.status === 200, "test order acceptance failed");

    await assertDuration(server, sellerToken, orderId, 15);
    await assertDuration(server, sellerToken, orderId, 30);
    await assertDuration(server, sellerToken, orderId, 60);

    for (const invalidDuration of [0, -1, 61, "15"]) {
      const invalid = await jsonRequest(server, {
        method: "PATCH",
        path: `/orders/${orderId}/ready-time`,
        token: sellerToken,
        body: { readyInMinutes: invalidDuration },
      });
      assert(
        invalid.status === 400,
        `invalid readyInMinutes ${invalidDuration} must be rejected`
      );
    }

    const customReadyAt = new Date(Date.now() + 90 * 60 * 1000);
    const custom = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${orderId}/ready-time`,
      token: sellerToken,
      body: { expectedReadyAt: customReadyAt.toISOString() },
    });
    assert(custom.status === 200, "UTC custom ready time failed");
    assert(
      new Date(custom.json.expectedReadyAt).getTime() === customReadyAt.getTime(),
      "UTC custom ready time changed during storage"
    );

    const timezoneLess = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${orderId}/ready-time`,
      token: sellerToken,
      body: { expectedReadyAt: customReadyAt.toISOString().replace(/Z$/, "") },
    });
    assert(timezoneLess.status === 400, "timezone-less ready time must be rejected");

    const cleared = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${orderId}/ready-time`,
      token: sellerToken,
      body: { expectedReadyAt: null },
    });
    assert(cleared.status === 200, "clearing ready time failed");
    assert(cleared.json.expectedReadyAt === null, "ready time was not cleared");

    const buyerGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${orderId}`,
      token: buyerToken,
    });
    assert(buyerGet.status === 200, "buyer could not get own order");
    assert(buyerGet.json.id === orderId, "GET order returned the wrong order");
    assert(
      buyerGet.json.orderId &&
        buyerGet.json.status &&
        buyerGet.json.paymentStatus &&
        Array.isArray(buyerGet.json.items) &&
        buyerGet.json.timeline,
      "GET order does not match serializeOrder structure"
    );

    const sellerGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${orderId}`,
      token: sellerToken,
    });
    assert(sellerGet.status === 200, "seller could not get their order");

    const forbiddenGet = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${orderId}`,
      token: otherBuyerToken,
    });
    assert(forbiddenGet.status === 403, "another buyer could read the order");

    const stats = await jsonRequest(server, {
      method: "GET",
      path: "/orders/seller/stats",
      token: sellerToken,
    });
    assert(
      stats.status === 200,
      `/orders/seller/stats failed or was captured by /:id: ${stats.status} ${JSON.stringify(
        stats.json
      )}`
    );
    assert(
      typeof stats.json.todayOrders === "number",
      "seller stats response shape changed"
    );

    console.log("order reconciliation tests: all passed");
  } finally {
    if (orderId) await prisma.order.deleteMany({ where: { id: orderId } });
    if (listing) {
      await prisma.listing.deleteMany({ where: { id: listing.id } });
    }
    await prisma.user.deleteMany({ where: { phone: OTHER_BUYER_PHONE } });
    server.close();
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
