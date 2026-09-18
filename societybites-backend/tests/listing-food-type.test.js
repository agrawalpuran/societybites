require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const campaignRoutes = require("../routes/preorderCampaigns");
const { serializeListing } = require("../utils/listingSerializer");

const SELLER_PHONE = "+919901844776";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body)) : null;
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

function futureDates() {
  const orderOpenAt = new Date(Date.now() - 60 * 1000);
  const orderCutoffAt = new Date(Date.now() + 60 * 60 * 1000);
  const fulfilmentAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
  return { orderOpenAt, orderCutoffAt, fulfilmentAt };
}

async function main() {
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(seller && seller.societyId, "Seed seller with a society must exist");
  assert(seller.upiId, "Seed seller must have a UPI ID");

  const sellerToken = signToken(seller);
  const created = { listingIds: [], campaignIds: [] };

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/preorder-campaigns", campaignRoutes);
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
    const veg = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: { name: `Veg test ${Date.now()}`, price: 50, foodType: "VEG", category: "Lunch" },
    });
    assert(veg.status === 201, `VEG listing create failed: ${veg.status} ${JSON.stringify(veg.json)}`);
    assert(veg.json.foodType === "VEG", "serializer must return VEG");
    assert(Array.isArray(veg.json.categories) && veg.json.categories[0] === "Lunch", "categories array");
    created.listingIds.push(veg.json.id);

    const nonVeg = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: { name: `Non-veg test ${Date.now()}`, price: 80, foodType: "NON_VEG", category: "Dinner" },
    });
    assert(nonVeg.status === 201, `NON_VEG listing create failed: ${nonVeg.status}`);
    assert(nonVeg.json.foodType === "NON_VEG", "serializer must return NON_VEG");
    created.listingIds.push(nonVeg.json.id);

    const invalid = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: { name: `Invalid type ${Date.now()}`, price: 40, foodType: "EGG" },
    });
    assert(invalid.status === 400, `invalid foodType must be 400, got ${invalid.status}`);

    const missing = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: { name: `Missing type ${Date.now()}`, price: 40 },
    });
    assert(missing.status === 400, `missing foodType must be 400, got ${missing.status}`);

    const eggOnVeg = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Egg veg ${Date.now()}`,
        price: 40,
        foodType: "VEG",
        tags: ["Egg"],
      },
    });
    assert(eggOnVeg.status === 400, "Egg tag with VEG must be rejected");

    const nullListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Legacy null foodType ${Date.now()}`,
        price: 25,
        quantity: 1,
        status: "active",
      },
    });
    created.listingIds.push(nullListing.id);
    const serializedNull = serializeListing(nullListing);
    assert(serializedNull.foodType === null, "existing NULL foodType must serialize as null");

    const fetched = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${nullListing.id}`,
      token: sellerToken,
    });
    assert(fetched.status === 200, "legacy listing GET must work");
    assert(fetched.json.foodType === null, "GET must keep NULL foodType");

    const dates = futureDates();
    const campaign = await jsonRequest(server, {
      method: "POST",
      path: "/preorder-campaigns",
      token: sellerToken,
      body: {
        title: `Food type campaign ${Date.now()}`,
        orderOpenAt: dates.orderOpenAt.toISOString(),
        orderCutoffAt: dates.orderCutoffAt.toISOString(),
        fulfilmentAt: dates.fulfilmentAt.toISOString(),
        status: "open",
        products: [
          { name: "Samosa", price: 20, inventoryMode: "demand", foodType: "VEG" },
        ],
      },
    });
    assert(campaign.status === 201, `campaign create failed: ${campaign.status} ${JSON.stringify(campaign.json)}`);
    created.campaignIds.push(campaign.json.id);
    const product = campaign.json.products[0];
    assert(product.foodType === "VEG", "pre-order product must accept foodType");
    created.listingIds.push(product.id);

    const patched = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.json.id}/products/${product.id}`,
      token: sellerToken,
      body: { foodType: "NON_VEG" },
    });
    assert(patched.status === 200, "pre-order product foodType update failed");
    assert(patched.json.foodType === "NON_VEG", "updated product foodType");
  } finally {
    await server.close();
    if (created.campaignIds.length) {
      await prisma.preOrderCampaign.deleteMany({
        where: { id: { in: created.campaignIds } },
      });
    }
    if (created.listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: created.listingIds } } });
    }
    await prisma.$disconnect();
  }

  console.log("listing-food-type tests passed");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
