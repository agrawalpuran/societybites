require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");

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

async function cleanupSociety(societyId) {
  if (!societyId) return;
  const users = await prisma.user.findMany({
    where: { societyId },
    select: { id: true },
  });
  const userIds = users.map((user) => user.id);
  if (userIds.length) {
    await prisma.review.deleteMany({
      where: { OR: [{ reviewerId: { in: userIds } }, { listing: { sellerId: { in: userIds } } }] },
    });
    await prisma.orderItem.deleteMany({
      where: { listing: { sellerId: { in: userIds } } },
    });
    await prisma.order.deleteMany({
      where: { OR: [{ buyerId: { in: userIds } }, { items: { some: { listing: { sellerId: { in: userIds } } } } }] },
    });
    await prisma.listing.deleteMany({ where: { sellerId: { in: userIds } } });
    await prisma.preOrderCampaign.deleteMany({ where: { sellerId: { in: userIds } } });
    await prisma.refreshToken.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.deviceToken.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  }
  await prisma.society.deleteMany({ where: { id: societyId } });
}

async function createSociety(name, city) {
  return prisma.society.create({
    data: {
      name,
      city,
      inviteCode: `GK${Math.random().toString(36).slice(2, 10)}`,
    },
  });
}

async function createSeller({ phone, societyId, reach, name }) {
  return prisma.user.create({
    data: {
      phone,
      name: name || `Seller ${phone.slice(-4)}`,
      role: "seller",
      societyId,
      sellingReachLevel: reach,
      upiId: "hidden@upi",
      upiDisplayName: "Hidden UPI",
    },
  });
}

async function createListing({ sellerId, societyId, name, catalogType, status, campaignId }) {
  return prisma.listing.create({
    data: {
      sellerId,
      societyId,
      name,
      price: 120,
      quantity: 4,
      status: status || "active",
      catalogType: catalogType || "REGULAR",
      category: "Lunch",
      campaignId: campaignId || null,
    },
  });
}

function kitchenIds(payload) {
  return (payload.kitchens || []).map((item) => item.seller && item.seller.id);
}

async function main() {
  const stamp = String(Date.now()).slice(-8);
  const bangalore = await createSociety(`Guest BLR ${stamp}`, "Bangalore");
  const pune = await createSociety(`Guest Pune ${stamp}`, "Pune");
  const ids = { bangalore: bangalore.id, pune: pune.id };

  const nearby = await createSeller({
    phone: `+91970${stamp}1`,
    societyId: bangalore.id,
    reach: "NEARBY",
    name: "Guest Nearby Kitchen",
  });
  const extended = await createSeller({
    phone: `+91970${stamp}2`,
    societyId: bangalore.id,
    reach: "EXTENDED",
    name: "Guest Extended Kitchen",
  });
  const mySociety = await createSeller({
    phone: `+91970${stamp}3`,
    societyId: bangalore.id,
    reach: "MY_SOCIETY",
    name: "Guest My Society Kitchen",
  });
  const noListing = await createSeller({
    phone: `+91970${stamp}4`,
    societyId: bangalore.id,
    reach: "NEARBY",
    name: "Guest Empty Kitchen",
  });
  const preorderOnly = await createSeller({
    phone: `+91970${stamp}5`,
    societyId: bangalore.id,
    reach: "NEARBY",
    name: "Guest Preorder Kitchen",
  });
  const otherCity = await createSeller({
    phone: `+91970${stamp}6`,
    societyId: pune.id,
    reach: "NEARBY",
    name: "Guest Pune Kitchen",
  });
  const buyer = await prisma.user.create({
    data: {
      phone: `+91970${stamp}7`,
      name: "Guest Buyer",
      role: "buyer",
      societyId: bangalore.id,
    },
  });

  await createListing({
    sellerId: nearby.id,
    societyId: bangalore.id,
    name: "Guest Regular Bowl",
  });
  await createListing({
    sellerId: extended.id,
    societyId: bangalore.id,
    name: "Guest Extended Thali",
  });
  await createListing({
    sellerId: mySociety.id,
    societyId: bangalore.id,
    name: "Hidden Society Meal",
  });
  const campaign = await prisma.preOrderCampaign.create({
    data: {
      sellerId: preorderOnly.id,
      societyId: bangalore.id,
      title: "Guest Campaign",
      orderOpenAt: new Date(Date.now() - 3600_000),
      orderCutoffAt: new Date(Date.now() + 86400_000),
      fulfilmentAt: new Date(Date.now() + 172800_000),
      status: "open",
    },
  });
  await createListing({
    sellerId: preorderOnly.id,
    societyId: bangalore.id,
    name: "Guest Preorder Box",
    catalogType: "PREORDER",
    campaignId: campaign.id,
  });
  await createListing({
    sellerId: otherCity.id,
    societyId: pune.id,
    name: "Pune Regular Meal",
  });

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  try {
    const unauth = await jsonRequest(server, {
      method: "GET",
      path: "/listings/guest-kitchens?city=bengaluru",
    });
    assert(unauth.status === 200, `guest kitchens should be public, got ${unauth.status}`);
    assert(unauth.json.cityKey === "bengaluru", "cityKey bengaluru");
    assert(unauth.json.cityName === "Bengaluru", "display Bengaluru");
    const returned = kitchenIds(unauth.json);
    assert(returned.includes(nearby.id), "NEARBY kitchen included");
    assert(returned.includes(extended.id), "EXTENDED kitchen included");
    assert(!returned.includes(mySociety.id), "MY_SOCIETY excluded");
    assert(!returned.includes(noListing.id), "no regular listings excluded");
    assert(!returned.includes(preorderOnly.id), "PREORDER-only excluded");
    assert(!returned.includes(otherCity.id), "other city excluded");

    const alias = await jsonRequest(server, {
      method: "GET",
      path: "/listings/guest-kitchens?city=Bangalore",
    });
    assert(alias.status === 200, "Bangalore alias works");
    assert(alias.json.cityKey === "bengaluru", "Bangalore canonicalizes");

    const kitchen = (unauth.json.kitchens || []).find(
      (item) => item.seller.id === nearby.id
    );
    assert(kitchen, "nearby kitchen payload");
    const kitchenText = JSON.stringify(kitchen);
    assert(!kitchenText.includes("hidden@upi"), "UPI not returned");
    assert(!kitchenText.includes("Hidden UPI"), "UPI display not returned");
    assert(!kitchenText.includes(nearby.phone || "+91970"), "phone not returned");
    assert(!/upiId|phone|flatNumber/.test(kitchenText), "private field names absent");

    const storefront = await jsonRequest(server, {
      method: "GET",
      path: `/listings/guest-kitchens/${nearby.id}?city=bengaluru`,
    });
    assert(storefront.status === 200, "guest storefront public");
    assert(storefront.json.seller.name === "Guest Nearby Kitchen", "storefront name");
    assert(
      (storefront.json.listings || []).some((item) => item.name === "Guest Regular Bowl"),
      "REGULAR listing visible"
    );
    assert(
      !(storefront.json.listings || []).some((item) => item.catalogType === "PREORDER"),
      "no PREORDER in storefront"
    );
    const storeText = JSON.stringify(storefront.json);
    assert(!storeText.includes("hidden@upi"), "storefront omits UPI");

    const hiddenStore = await jsonRequest(server, {
      method: "GET",
      path: `/listings/guest-kitchens/${mySociety.id}`,
    });
    assert(hiddenStore.status === 404, "MY_SOCIETY storefront hidden");

    const nearbyAuth = await jsonRequest(server, {
      method: "GET",
      path: "/listings/nearby-sellers",
    });
    assert(nearbyAuth.status === 401, "authenticated nearby still requires auth");

    const orderAuth = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      body: { items: [{ listingId: "x", quantity: 1 }] },
    });
    assert(orderAuth.status === 401, "orders still require auth");

    const buyerToken = signToken(buyer);
    const nearbyWithToken = await jsonRequest(server, {
      method: "GET",
      path: "/listings/nearby-sellers",
      token: buyerToken,
    });
    assert(
      nearbyWithToken.status === 200 || nearbyWithToken.status === 400,
      "nearby endpoint still exists for authenticated buyers"
    );

    console.log("guest-kitchens.test.js: PASS");
  } finally {
    server.close();
    await cleanupSociety(ids.bangalore);
    await cleanupSociety(ids.pune);
    await prisma.$disconnect();
  }
}

main().catch(async (err) => {
  console.error("guest-kitchens.test.js: FAIL");
  console.error(err);
  try {
    await prisma.$disconnect();
  } catch (_) {}
  process.exit(1);
});
