require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const {
  resolveCreateListingStatus,
  draftIdsToPublish,
} = require("../lib/listingPublish");

const SEED_SELLER_PHONE = "+919901844776";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(resolveCreateListingStatus({}) === "draft", "default draft");
assert(resolveCreateListingStatus({ publish: true }) === "active", "publish now");
assert(resolveCreateListingStatus({ publish: false }) === "draft", "publish false");

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
  const stamp = Date.now();
  const seller = await prisma.user.findUnique({
    where: { phone: SEED_SELLER_PHONE },
  });
  assert(seller && seller.societyId && seller.upiId, "seed seller with UPI");

  const sellerToken = signToken(seller);
  const listingIds = [];

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
      code: err.code,
    });
  });

  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const draft = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Draft dish ${stamp}`,
        price: 120,
        foodType: "VEG",
        category: "Lunch",
        quantity: 3,
      },
    });
    assert(draft.status === 201, `create draft ${JSON.stringify(draft.json)}`);
    assert(draft.json.status === "draft", "created as draft");
    listingIds.push(draft.json.id);

    const live = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Live dish ${stamp}`,
        price: 90,
        foodType: "VEG",
        category: "Snacks",
        quantity: 2,
        publish: true,
      },
    });
    assert(live.status === 201, `create published ${JSON.stringify(live.json)}`);
    assert(live.json.status === "active", "publish:true creates active");
    listingIds.push(live.json.id);

    const published = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${draft.json.id}/publish`,
      token: sellerToken,
    });
    assert(
      published.status === 200,
      `publish one ${JSON.stringify(published.json)}`
    );
    assert(published.json.status === "active", "draft becomes active");

    const draft2 = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Draft two ${stamp}`,
        price: 50,
        foodType: "VEG",
        category: "Dinner",
        quantity: 1,
      },
    });
    assert(draft2.status === 201, "draft2");
    listingIds.push(draft2.json.id);
    const draft3 = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Draft three ${stamp}`,
        price: 55,
        foodType: "VEG",
        category: "Dinner",
        quantity: 1,
      },
    });
    assert(draft3.status === 201, "draft3");
    listingIds.push(draft3.json.id);

    const bulk = await jsonRequest(server, {
      method: "PATCH",
      path: "/listings/bulk/publish",
      token: sellerToken,
    });
    assert(bulk.status === 200, `bulk publish ${JSON.stringify(bulk.json)}`);
    assert(bulk.json.publishedCount >= 2, "publishes remaining drafts");

    const ids = await draftIdsToPublish(prisma, {
      id: "x",
      status: "active",
      sellerId: seller.id,
    });
    assert(ids.length === 0, "non-draft yields no ids");

    console.log("listing-draft-publish.test.js passed");
  } finally {
    server.close();
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
