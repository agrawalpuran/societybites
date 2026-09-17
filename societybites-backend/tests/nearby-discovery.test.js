require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");

const SEED_BUYER_PHONE = "+919845154070";
const SEED_SELLER_PHONE = "+919901844776";
const OTHER_SOCIETY_ID = "brigade-gateway";
const CITY_KEY = "phase4bville";

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

async function createSociety(name, extras) {
  return prisma.society.create({
    data: {
      name,
      city: extras.city || "Phase4B Ville",
      inviteCode: `P4B${Math.random().toString(36).slice(2, 10)}`,
      latitude: extras.latitude === undefined ? 12.9716 : extras.latitude,
      longitude: extras.longitude === undefined ? 77.5946 : extras.longitude,
    },
  });
}

async function createUser({ phone, societyId, role, reach, fulfilmentMode, deliveryCharge }) {
  return prisma.user.create({
    data: {
      phone,
      name: phone.slice(-4),
      role: role || "seller",
      societyId,
      sellingReachLevel: reach || "MY_SOCIETY",
      fulfilmentMode: fulfilmentMode || "BUYER_PICKUP",
      deliveryCharge: deliveryCharge == null ? 0 : deliveryCharge,
      upiId: role === "buyer" ? null : "seller@upi",
    },
  });
}

async function createListing(seller, name, extras = {}) {
  return prisma.listing.create({
    data: {
      sellerId: seller.id,
      societyId: extras.societyId || seller.societyId,
      name,
      price: 80,
      quantity: 1,
      status: extras.status || "active",
    },
  });
}

function sellerIds(payload) {
  return (payload.sellers || []).map((card) => card.seller.id);
}

async function main() {
  const stamp = Date.now();
  const createdListingIds = [];
  const createdUserIds = [];
  const createdSocietyIds = [];
  let createdCityConfig = false;

  const buyerSociety = await createSociety(`P4B Buyer ${stamp}`, {
    latitude: 12.9716,
    longitude: 77.5946,
  });
  createdSocietyIds.push(buyerSociety.id);

  const nearbyInsideSociety = await createSociety(`P4B NearIn ${stamp}`, {
    latitude: 12.9986,
    longitude: 77.5946,
  });
  createdSocietyIds.push(nearbyInsideSociety.id);

  const nearbyOutsideSociety = await createSociety(`P4B NearOut ${stamp}`, {
    latitude: 13.0436,
    longitude: 77.5946,
  });
  createdSocietyIds.push(nearbyOutsideSociety.id);

  const extendedOutsideSociety = await createSociety(`P4B ExtOut ${stamp}`, {
    latitude: 13.1066,
    longitude: 77.5946,
  });
  createdSocietyIds.push(extendedOutsideSociety.id);

  const noCoordSociety = await createSociety(`P4B NoCoord ${stamp}`, {
    latitude: null,
    longitude: null,
  });
  createdSocietyIds.push(noCoordSociety.id);

  const puneSociety = await createSociety(`P4B Pune ${stamp}`, {
    city: "Pune",
    latitude: 18.52,
    longitude: 73.85,
  });
  createdSocietyIds.push(puneSociety.id);

  const buyer = await createUser({
    phone: `+91970${String(stamp).slice(-7)}`,
    societyId: buyerSociety.id,
    role: "buyer",
    reach: "MY_SOCIETY",
  });
  createdUserIds.push(buyer.id);

  const sameSocietySeller = await createUser({
    phone: `+91971${String(stamp).slice(-7)}`,
    societyId: buyerSociety.id,
    role: "seller",
    reach: "MY_SOCIETY",
  });
  createdUserIds.push(sameSocietySeller.id);

  const mySocietyOther = await createUser({
    phone: `+91972${String(stamp).slice(-7)}`,
    societyId: nearbyInsideSociety.id,
    role: "seller",
    reach: "MY_SOCIETY",
  });
  createdUserIds.push(mySocietyOther.id);

  const nearbyInside = await createUser({
    phone: `+91973${String(stamp).slice(-7)}`,
    societyId: nearbyInsideSociety.id,
    role: "seller",
    reach: "NEARBY",
    fulfilmentMode: "SELLER_DELIVERY",
    deliveryCharge: 40,
  });
  createdUserIds.push(nearbyInside.id);

  const nearbyOutside = await createUser({
    phone: `+91974${String(stamp).slice(-7)}`,
    societyId: nearbyOutsideSociety.id,
    role: "seller",
    reach: "NEARBY",
  });
  createdUserIds.push(nearbyOutside.id);

  const extendedInside = await createUser({
    phone: `+91975${String(stamp).slice(-7)}`,
    societyId: nearbyOutsideSociety.id,
    role: "seller",
    reach: "EXTENDED",
  });
  createdUserIds.push(extendedInside.id);

  const extendedOutside = await createUser({
    phone: `+91976${String(stamp).slice(-7)}`,
    societyId: extendedOutsideSociety.id,
    role: "seller",
    reach: "EXTENDED",
  });
  createdUserIds.push(extendedOutside.id);

  const noCoordSeller = await createUser({
    phone: `+91977${String(stamp).slice(-7)}`,
    societyId: noCoordSociety.id,
    role: "seller",
    reach: "NEARBY",
  });
  createdUserIds.push(noCoordSeller.id);

  const puneSeller = await createUser({
    phone: `+91978${String(stamp).slice(-7)}`,
    societyId: puneSociety.id,
    role: "seller",
    reach: "EXTENDED",
  });
  createdUserIds.push(puneSeller.id);

  const noListingSeller = await createUser({
    phone: `+91979${String(stamp).slice(-7)}`,
    societyId: nearbyInsideSociety.id,
    role: "seller",
    reach: "NEARBY",
  });
  createdUserIds.push(noListingSeller.id);

  const pausedSeller = await createUser({
    phone: `+91980${String(stamp).slice(-7)}`,
    societyId: nearbyInsideSociety.id,
    role: "seller",
    reach: "NEARBY",
  });
  createdUserIds.push(pausedSeller.id);

  const listings = await Promise.all([
    createListing(sameSocietySeller, `Same society ${stamp}`),
    createListing(mySocietyOther, `Other MY_SOCIETY ${stamp}`),
    createListing(nearbyInside, `Nearby inside ${stamp}`),
    createListing(nearbyOutside, `Nearby outside ${stamp}`),
    createListing(extendedInside, `Extended inside ${stamp}`),
    createListing(extendedOutside, `Extended outside ${stamp}`),
    createListing(noCoordSeller, `No coord ${stamp}`),
    createListing(puneSeller, `Pune ${stamp}`),
    createListing(pausedSeller, `Paused ${stamp}`, { status: "paused" }),
  ]);
  createdListingIds.push(...listings.map((item) => item.id));

  await prisma.cityReachConfig.upsert({
    where: { cityKey: CITY_KEY },
    create: {
      cityKey: CITY_KEY,
      displayName: "Phase4B Ville",
      nearbyRadiusKm: 5,
      extendedRadiusKm: 10,
    },
    update: {
      nearbyRadiusKm: 5,
      extendedRadiusKm: 10,
    },
  });
  createdCityConfig = true;

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
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
    const token = signToken(buyer);
    const nearby = await jsonRequest(server, {
      method: "GET",
      path: "/listings/nearby-sellers?nearbyRadiusKm=999&distanceKm=0",
      token,
    });
    assert(nearby.status === 200, `nearby discovery failed: ${nearby.status}`);
    assert(nearby.json.available === true, "nearby should be available");
    assert(nearby.json.appliedRadiusKm === 10, "applied radius comes from city config");
    assert(nearby.json.nearbyRadiusKm === 5, "nearby radius from city config");
    const ids = sellerIds(nearby.json);

    assert(ids.includes(sameSocietySeller.id), "same-society seller appears");
    assert(!ids.includes(mySocietyOther.id), "MY_SOCIETY seller from another society hidden");
    assert(ids.includes(nearbyInside.id), "NEARBY seller within radius appears");
    assert(!ids.includes(nearbyOutside.id), "NEARBY seller outside radius hidden");
    assert(ids.includes(extendedInside.id), "EXTENDED seller within extended radius appears");
    assert(!ids.includes(extendedOutside.id), "EXTENDED seller outside extended radius hidden");
    assert(!ids.includes(puneSeller.id), "different city seller hidden");
    assert(!ids.includes(noCoordSeller.id), "missing seller coordinates excluded");
    assert(!ids.includes(noListingSeller.id), "seller with no listings hidden");
    assert(!ids.includes(pausedSeller.id), "seller with no active listings hidden");

    const distances = nearby.json.sellers.map((card) => card.seller.distanceKm);
    const sorted = [...distances].sort((a, b) => a - b);
    assert(JSON.stringify(distances) === JSON.stringify(sorted), "sellers sorted by distance");

    const nearbyCard = nearby.json.sellers.find((card) => card.seller.id === nearbyInside.id);
    assert(nearbyCard.fulfilment.mode === "SELLER_DELIVERY", "fulfilment mode on card");
    assert(nearbyCard.fulfilment.deliveryCharge === 40, "delivery charge on card");
    assert(nearbyCard.listings.length >= 1, "listings bundled without N+1");

    const storefront = await jsonRequest(server, {
      method: "GET",
      path: `/listings/nearby-sellers/${nearbyInside.id}?nearbyRadiusKm=0`,
      token,
    });
    assert(storefront.status === 200, "eligible nearby storefront succeeds");
    assert(storefront.json.seller.id === nearbyInside.id, "storefront seller id");

    const blockedStorefront = await jsonRequest(server, {
      method: "GET",
      path: `/listings/nearby-sellers/${mySocietyOther.id}`,
      token,
    });
    assert(blockedStorefront.status === 404, "ineligible nearby storefront is 404");

    const outsideStorefront = await jsonRequest(server, {
      method: "GET",
      path: `/listings/nearby-sellers/${nearbyOutside.id}`,
      token,
    });
    assert(outsideStorefront.status === 404, "out-of-radius storefront is 404");

    await prisma.society.update({
      where: { id: buyerSociety.id },
      data: { latitude: null, longitude: null },
    });
    const missingBuyer = await jsonRequest(server, {
      method: "GET",
      path: "/listings/nearby-sellers",
      token,
    });
    assert(missingBuyer.status === 200, "missing buyer coords is graceful");
    assert(missingBuyer.json.available === false, "nearby unavailable without buyer coords");
    assert(missingBuyer.json.reason === "BUYER_COORDINATES_MISSING", "buyer coords reason");
    assert(missingBuyer.json.sellers.length === 0, "no sellers when unavailable");

    await prisma.society.update({
      where: { id: buyerSociety.id },
      data: { latitude: 12.9716, longitude: 77.5946 },
    });

    await prisma.cityReachConfig.delete({ where: { cityKey: CITY_KEY } });
    createdCityConfig = false;
    const missingConfig = await jsonRequest(server, {
      method: "GET",
      path: "/listings/nearby-sellers",
      token,
    });
    assert(missingConfig.status === 200, "missing city config is graceful");
    assert(missingConfig.json.available === false, "unavailable without city config");
    assert(missingConfig.json.reason === "CITY_CONFIG_MISSING", "missing config reason");
    assert(missingConfig.json.appliedRadiusKm == null, "does not invent a radius");

    const seedBuyer = await prisma.user.findUnique({ where: { phone: SEED_BUYER_PHONE } });
    const seedSeller = await prisma.user.findUnique({ where: { phone: SEED_SELLER_PHONE } });
    assert(seedBuyer && seedSeller, "seed users required for society-scope checks");
    assert(seedBuyer.societyId !== OTHER_SOCIETY_ID, "seed buyer must not be other society");

    const otherListing = await prisma.listing.create({
      data: {
        sellerId: seedSeller.id,
        societyId: OTHER_SOCIETY_ID,
        name: `P4B other-society ${stamp}`,
        price: 80,
        quantity: 1,
        status: "active",
      },
    });
    createdListingIds.push(otherListing.id);

    const seedToken = signToken(seedBuyer);
    const listings = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token: seedToken,
    });
    assert(listings.status === 200, "GET /listings failed");
    assert(
      listings.json.every((item) => item.societyId === seedBuyer.societyId),
      "GET /listings remains society-scoped"
    );
    assert(
      !listings.json.some((item) => item.id === otherListing.id),
      "GET /listings hides other-society listing"
    );

    const detail = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${otherListing.id}`,
      token: seedToken,
    });
    assert(detail.status === 404, "GET /listings/:id remains society-scoped");

    const order = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: seedToken,
      body: {
        items: [{ listingId: otherListing.id, quantity: 1 }],
        paymentMethod: "upi",
      },
    });
    assert(order.status === 400, "POST /orders remains cross-society blocked");
  } finally {
    server.close();
    if (createdListingIds.length) {
      await prisma.orderItem.deleteMany({ where: { listingId: { in: createdListingIds } } }).catch(() => {});
      await prisma.listing.deleteMany({ where: { id: { in: createdListingIds } } });
    }
    if (createdUserIds.length) {
      await prisma.refreshToken.deleteMany({ where: { userId: { in: createdUserIds } } }).catch(() => {});
      await prisma.user.deleteMany({ where: { id: { in: createdUserIds } } });
    }
    if (createdSocietyIds.length) {
      await prisma.society.deleteMany({ where: { id: { in: createdSocietyIds } } });
    }
    if (createdCityConfig) {
      await prisma.cityReachConfig.delete({ where: { cityKey: CITY_KEY } }).catch(() => {});
    }
  }
}

main()
  .then(() => {
    console.log("nearby-discovery tests passed");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
