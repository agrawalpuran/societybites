require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const {
  DEFAULT_FULFILMENT_MODE,
  parseDeliveryCharge,
} = require("../lib/sellerFulfilment");
const authRoutes = require("../routes/auth");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_SOCIETY_ID = "brigade-gateway";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function expectThrow(fn, snippet) {
  try {
    fn();
    throw new Error("expected an error");
  } catch (err) {
    if (err.message === "expected an error") throw err;
    assert(String(err.message).includes(snippet), `unexpected: ${err.message}`);
  }
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
  expectThrow(() => parseDeliveryCharge(-1), ">=");
  assert(parseDeliveryCharge(0) === 0, "zero charge");
  assert(parseDeliveryCharge(40) === 40, "positive charge");

  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  const buyer = await prisma.user.findUnique({
    where: { phone: BUYER_PHONE },
    include: { society: true },
  });
  assert(seller && buyer, "seed seller and buyer required");

  const original = {
    fulfilmentMode: seller.fulfilmentMode,
    deliveryCharge: seller.deliveryCharge,
    sellingReachLevel: seller.sellingReachLevel,
  };

  const reachBuyer = await prisma.user.create({
    data: {
      phone: `+9198${String(Date.now()).slice(-8)}`,
      role: "buyer",
      societyId: buyer.societyId,
    },
  });

  await prisma.user.update({
    where: { id: seller.id },
    data: { fulfilmentMode: "BUYER_PICKUP", deliveryCharge: 0, sellingReachLevel: "MY_SOCIETY" },
  });

  const sellerToken = signToken(seller);
  const reachBuyerToken = signToken(reachBuyer);
  const buyerToken = signToken(buyer);

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
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
  try {
    const me = await jsonRequest(server, { method: "GET", path: "/auth/me", token: sellerToken });
    assert(me.status === 200, "GET /me failed");
    assert(me.json.fulfilmentMode === DEFAULT_FULFILMENT_MODE, "default fulfilment BUYER_PICKUP");
    assert(me.json.fulfilment.mode === "BUYER_PICKUP", "/auth/me fulfilment.mode");
    assert(me.json.fulfilment.deliveryCharge === null, "pickup hides delivery charge");
    assert(me.json.sellingReachLevel === "MY_SOCIETY", "sellingReach intact");
    assert(me.json.sellingReach, "sellingReach object intact");

    const pickup = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { fulfilmentMode: "BUYER_PICKUP" },
    });
    assert(pickup.status === 200, "seller can select BUYER_PICKUP");
    assert(pickup.json.user.fulfilment.mode === "BUYER_PICKUP", "pickup persisted");

    const unknown = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { fulfilmentMode: "DRONE" },
    });
    assert(unknown.status === 400, "unknown fulfilment mode rejected");

    const negative = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { fulfilmentMode: "SELLER_DELIVERY", deliveryCharge: -10 },
    });
    assert(negative.status === 400, "negative delivery charge rejected");

    const zero = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { fulfilmentMode: "SELLER_DELIVERY", deliveryCharge: 0 },
    });
    assert(zero.status === 200, "zero delivery charge accepted");
    assert(zero.json.user.fulfilment.mode === "SELLER_DELIVERY", "seller delivery persisted");
    assert(zero.json.user.fulfilment.deliveryCharge === 0, "zero charge stored");

    const positive = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { fulfilmentMode: "BOTH", deliveryCharge: 40 },
    });
    assert(positive.status === 200, "BOTH accepted");
    assert(positive.json.user.fulfilment.mode === "BOTH", "both persisted");
    assert(positive.json.user.fulfilment.deliveryCharge === 40, "positive charge stored");
    assert(positive.json.user.sellingReachLevel === "MY_SOCIETY", "reach unchanged by fulfilment");

    const buyerBlocked = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: reachBuyerToken,
      body: { fulfilmentMode: "SELLER_DELIVERY", deliveryCharge: 25 },
    });
    assert(buyerBlocked.status === 400, "buyer cannot modify fulfilment");

    const otherListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: OTHER_SOCIETY_ID,
        name: `Fulfilment other-society ${Date.now()}`,
        price: 70,
        quantity: 1,
        status: "active",
      },
    });
    listingIds.push(otherListing.id);

    const listings = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token: buyerToken,
    });
    assert(listings.status === 200, "GET /listings failed");
    assert(
      listings.json.every((item) => item.societyId === buyer.societyId),
      "listings remain society-scoped"
    );
    assert(!listings.json.some((item) => item.id === otherListing.id), "other society hidden");

    const detail = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${otherListing.id}`,
      token: buyerToken,
    });
    assert(detail.status === 404, "listing detail remains society-scoped");

    const order = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: otherListing.id, quantity: 1 }],
      },
    });
    assert(order.status === 400, "cross-society order remains rejected");
  } finally {
    await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    await prisma.user.deleteMany({ where: { id: reachBuyer.id } });
    await prisma.user.update({
      where: { id: seller.id },
      data: {
        fulfilmentMode: original.fulfilmentMode || "BUYER_PICKUP",
        deliveryCharge: original.deliveryCharge || 0,
        sellingReachLevel: original.sellingReachLevel || "MY_SOCIETY",
      },
    });
    await new Promise((resolve) => server.close(resolve));
  }
}

main()
  .then(() => {
    console.log("seller-fulfilment tests passed");
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
