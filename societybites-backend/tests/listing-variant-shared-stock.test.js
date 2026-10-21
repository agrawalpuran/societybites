require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");

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
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  app.use((error, _req, res, _next) => {
    const statusCode = error.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : error.message,
      availableQuantity: error.availableQuantity,
    });
  });

  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const createdIds = [];
  try {
    const created = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Shared paneer ${Date.now()}`,
        price: 80,
        quantity: 1000,
        foodType: "VEG",
        categories: ["Dairy"],
        publish: true,
        variantInventoryMode: "SHARED",
        sharedPoolQuantity: 1000,
        variants: [
          { label: "250 g", price: 80, portionUnits: 250 },
          { label: "500 g", price: 150, portionUnits: 500 },
        ],
      },
    });
    assert(
      created.status === 201,
      `create shared: ${created.status} ${JSON.stringify(created.json)}`
    );
    assert(created.json.variantInventoryMode === "SHARED", "mode on payload");
    assert(created.json.portionUnits === 250 || created.json.portionUnits === 500, "portion");
    assert(created.json.poolQuantity === 1000, "pool on payload");
    assert(
      created.json.quantity === Math.floor(1000 / created.json.portionUnits),
      "orderable quantity"
    );

    const groupId = created.json.variantGroupId;
    assert(groupId, "variant group");
    const siblings = await prisma.listing.findMany({
      where: { variantGroupId: groupId },
    });
    createdIds.push(...siblings.map((s) => s.id));
    assert(siblings.length === 2, "two siblings");
    assert(
      siblings.every((s) => s.quantity === 1000),
      "both store pool qty"
    );

    const size500 = siblings.find((s) => s.portionUnits === 500);
    assert(size500, "500g sibling");

    const order = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: size500.id, quantity: 2 }],
      },
    });
    assert(
      order.status === 201,
      `order 2x500: ${order.status} ${JSON.stringify(order.json)}`
    );

    const after = await prisma.listing.findMany({
      where: { variantGroupId: groupId },
    });
    assert(
      after.every((s) => s.quantity === 0),
      `pool depleted, got ${after.map((s) => s.quantity)}`
    );

    const oversell = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: size500.id, quantity: 1 }],
      },
    });
    assert(
      oversell.status === 409 || oversell.status === 400,
      `oversell blocked: ${oversell.status}`
    );

    console.log("listing-variant-shared-stock.test.js passed");
  } finally {
    await new Promise((resolve, reject) =>
      server.close((err) => (err ? reject(err) : resolve()))
    );
    if (createdIds.length) {
      await prisma.orderItem.deleteMany({
        where: { listingId: { in: createdIds } },
      });
      const orderIds = (
        await prisma.order.findMany({
          where: { items: { some: { listingId: { in: createdIds } } } },
          select: { id: true },
        })
      ).map((o) => o.id);
      if (orderIds.length) {
        await prisma.message.deleteMany({ where: { orderId: { in: orderIds } } });
        await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
      }
      await prisma.listing.deleteMany({ where: { id: { in: createdIds } } });
    }
    await prisma.$disconnect().catch(() => {});
  }
}

main()
  .then(() => process.exit(0))
  .catch(async (err) => {
    console.error(err);
    await prisma.$disconnect().catch(() => {});
    process.exit(1);
  });
