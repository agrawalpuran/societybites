require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const {
  shouldExposeSellerFlatNumber,
  redactSellerFlatOnListingPayload,
} = require("../lib/sellerFlatPrivacy");
const { serializeListing, serializeOrder } = require("../utils/listingSerializer");
const authRoutes = require("../routes/auth");
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
  const seller = { id: "s1", hideFlatNumber: true };
  const buyerId = "b1";
  assert(
    !shouldExposeSellerFlatNumber({ seller, viewerUserId: buyerId }),
    "buyer cannot see hidden flat on listing"
  );
  assert(
    shouldExposeSellerFlatNumber({ seller, viewerUserId: seller.id }),
    "seller sees own flat"
  );
  assert(
    shouldExposeSellerFlatNumber({
      seller,
      viewerUserId: buyerId,
      order: {
        buyerId,
        status: "accepted",
        fulfilmentMethod: "pickup",
      },
      pickupLocation: "My Home (Verified)",
    }),
    "buyer sees flat on accepted self-pickup at verified home"
  );
  assert(
    !shouldExposeSellerFlatNumber({
      seller,
      viewerUserId: buyerId,
      order: {
        buyerId,
        status: "accepted",
        fulfilmentMethod: "seller_delivery",
      },
      pickupLocation: "My Home (Verified)",
    }),
    "delivery order does not reveal flat"
  );

  const redacted = redactSellerFlatOnListingPayload(
    { flatNumber: "101", sellerId: seller.id },
    { seller, viewerUserId: buyerId }
  );
  assert(redacted.flatNumber === null, "payload redacted");

  const listing = serializeListing(
    {
      id: "l1",
      name: "Test",
      price: 10,
      quantity: 1,
      sellerId: seller.id,
      pickupLocation: "My Home (Verified)",
      seller: {
        id: seller.id,
        hideFlatNumber: true,
        name: "Chef",
        flat: { flatNumber: "3062", block: "A" },
      },
    },
    { viewerUserId: buyerId }
  );
  assert(listing.flatNumber === null, "serializeListing hides flat for buyer");

  const pendingOrder = serializeOrder(
    {
      id: "o1",
      buyerId,
      status: "pending",
      fulfilmentMethod: "pickup",
      items: [
        {
          id: "oi1",
          quantity: 1,
          unitPrice: 10,
          listing: {
            id: "l1",
            name: "Test",
            price: 10,
            quantity: 1,
            sellerId: seller.id,
            pickupLocation: "My Home (Verified)",
            seller: {
              id: seller.id,
              hideFlatNumber: true,
              name: "Chef",
              flat: { flatNumber: "3062", block: "A" },
            },
          },
        },
      ],
    },
    { viewerUserId: buyerId }
  );
  assert(
    pendingOrder.items[0].listing.flatNumber == null,
    "pending order does not reveal seller flat"
  );

  const orderPayload = serializeOrder(
    {
      id: "o2",
      buyerId,
      status: "accepted",
      fulfilmentMethod: "pickup",
      items: [
        {
          id: "oi1",
          quantity: 1,
          unitPrice: 10,
          listing: {
            id: "l1",
            name: "Test",
            price: 10,
            quantity: 1,
            sellerId: seller.id,
            pickupLocation: "My Home (Verified)",
            seller: {
              id: seller.id,
              hideFlatNumber: true,
              name: "Chef",
              flat: { flatNumber: "3062", block: "A" },
            },
          },
        },
      ],
    },
    { viewerUserId: buyerId }
  );
  assert(
    orderPayload.items[0].listing.flatNumber === "3062",
    "buyer sees seller flat on pickup order at verified home"
  );

  const seededSeller = await prisma.user.findUnique({
    where: { phone: SELLER_PHONE },
    include: { flat: true },
  });
  const seededBuyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  assert(seededSeller && seededBuyer, "seed seller and buyer required");

  const originalHide = Boolean(seededSeller.hideFlatNumber);
  const sellerToken = signToken(seededSeller);
  const buyerToken = signToken(seededBuyer);

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

  try {
    const enableHide = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { hideFlatNumber: true },
    });
    assert(enableHide.status === 200, "PATCH hideFlatNumber");
    assert(enableHide.json.user.hideFlatNumber === true, "hideFlatNumber persisted");

    const meSeller = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me",
      token: sellerToken,
    });
    assert(meSeller.status === 200, "GET /me seller");
    const sellerFlat =
      meSeller.json.flat && meSeller.json.flat.flatNumber;
    assert(sellerFlat, "seller still sees own flat on /me");

    const listings = await jsonRequest(server, {
      method: "GET",
      path: `/listings?sellerId=${seededSeller.id}&status=active`,
      token: buyerToken,
    });
    assert(listings.status === 200, "buyer lists seller catalog");
    if (Array.isArray(listings.json) && listings.json.length > 0) {
      const row = listings.json.find((item) => item.sellerId === seededSeller.id);
      if (row) {
        assert(row.flatNumber == null, "buyer listing payload hides seller flat");
      }
    }

    const restore = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { hideFlatNumber: originalHide },
    });
    assert(restore.status === 200, "restore hideFlatNumber");
  } finally {
    server.close();
    await prisma.$disconnect();
  }

  console.log("seller-flat-privacy.test.js OK");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
