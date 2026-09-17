require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");

const SEED_BUYER_PHONE = "+919845154070";
const SEED_SELLER_PHONE = "+919901844776";
const CITY_KEY = "phase5ville";

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

async function createSociety(name, extras = {}) {
  return prisma.society.create({
    data: {
      name,
      city: extras.city || "Phase5 Ville",
      inviteCode: `P5${Math.random().toString(36).slice(2, 10)}`,
      latitude: extras.latitude === undefined ? 12.9716 : extras.latitude,
      longitude: extras.longitude === undefined ? 77.5946 : extras.longitude,
    },
  });
}

async function createUser({ phone, societyId, role, reach, fulfilmentMode, deliveryCharge, name }) {
  return prisma.user.create({
    data: {
      phone,
      name: name || phone.slice(-4),
      role: role || "seller",
      societyId,
      sellingReachLevel: reach || "MY_SOCIETY",
      fulfilmentMode: fulfilmentMode || "BUYER_PICKUP",
      deliveryCharge: deliveryCharge == null ? 0 : deliveryCharge,
      upiId: role === "buyer" ? null : "seller@upi",
    },
  });
}

async function createListing(seller, name) {
  return prisma.listing.create({
    data: {
      sellerId: seller.id,
      societyId: seller.societyId,
      name,
      price: 80,
      quantity: 4,
      status: "active",
    },
  });
}

async function main() {
  const stamp = Date.now();
  const listingIds = [];
  const userIds = [];
  const societyIds = [];
  const orderIds = [];
  let createdCityConfig = false;

  const buyerSociety = await createSociety(`P5 Buyer ${stamp}`);
  societyIds.push(buyerSociety.id);
  const nearbySociety = await createSociety(`P5 Near ${stamp}`, {
    latitude: 12.9986,
    longitude: 77.5946,
  });
  societyIds.push(nearbySociety.id);
  const farSociety = await createSociety(`P5 Far ${stamp}`, {
    latitude: 13.0436,
    longitude: 77.5946,
  });
  societyIds.push(farSociety.id);
  const noCoordSociety = await createSociety(`P5 NoCoord ${stamp}`, {
    latitude: null,
    longitude: null,
  });
  societyIds.push(noCoordSociety.id);
  const puneSociety = await createSociety(`P5 Pune ${stamp}`, {
    city: "Pune",
    latitude: 18.52,
    longitude: 73.85,
  });
  societyIds.push(puneSociety.id);

  const buyer = await createUser({
    phone: `+91960${String(stamp).slice(-7)}`,
    societyId: buyerSociety.id,
    role: "buyer",
    name: "Phase5 Buyer",
  });
  userIds.push(buyer.id);

  const sameSeller = await createUser({
    phone: `+91961${String(stamp).slice(-7)}`,
    societyId: buyerSociety.id,
    reach: "MY_SOCIETY",
    name: "Same Society Cook",
  });
  userIds.push(sameSeller.id);

  const mySocietyOther = await createUser({
    phone: `+91962${String(stamp).slice(-7)}`,
    societyId: nearbySociety.id,
    reach: "MY_SOCIETY",
  });
  userIds.push(mySocietyOther.id);

  const nearbySeller = await createUser({
    phone: `+91963${String(stamp).slice(-7)}`,
    societyId: nearbySociety.id,
    reach: "NEARBY",
    fulfilmentMode: "BOTH",
    deliveryCharge: 30,
    name: "Nearby Cook",
  });
  userIds.push(nearbySeller.id);

  const farNearbySeller = await createUser({
    phone: `+91964${String(stamp).slice(-7)}`,
    societyId: farSociety.id,
    reach: "NEARBY",
    fulfilmentMode: "SELLER_DELIVERY",
    deliveryCharge: 20,
  });
  userIds.push(farNearbySeller.id);

  const extendedSeller = await createUser({
    phone: `+91965${String(stamp).slice(-7)}`,
    societyId: farSociety.id,
    reach: "EXTENDED",
    fulfilmentMode: "BUYER_PICKUP",
  });
  userIds.push(extendedSeller.id);

  const noCoordSeller = await createUser({
    phone: `+91966${String(stamp).slice(-7)}`,
    societyId: noCoordSociety.id,
    reach: "NEARBY",
  });
  userIds.push(noCoordSeller.id);

  const puneSeller = await createUser({
    phone: `+91967${String(stamp).slice(-7)}`,
    societyId: puneSociety.id,
    reach: "EXTENDED",
  });
  userIds.push(puneSeller.id);

  const pickupOnly = await createUser({
    phone: `+91968${String(stamp).slice(-7)}`,
    societyId: nearbySociety.id,
    reach: "NEARBY",
    fulfilmentMode: "BUYER_PICKUP",
  });
  userIds.push(pickupOnly.id);

  const deliveryOnly = await createUser({
    phone: `+91969${String(stamp).slice(-7)}`,
    societyId: nearbySociety.id,
    reach: "NEARBY",
    fulfilmentMode: "SELLER_DELIVERY",
    deliveryCharge: 25,
  });
  userIds.push(deliveryOnly.id);

  const listings = await Promise.all([
    createListing(sameSeller, `P5 same ${stamp}`),
    createListing(mySocietyOther, `P5 my-soc ${stamp}`),
    createListing(nearbySeller, `P5 nearby ${stamp}`),
    createListing(farNearbySeller, `P5 far-near ${stamp}`),
    createListing(extendedSeller, `P5 ext ${stamp}`),
    createListing(noCoordSeller, `P5 nocoord ${stamp}`),
    createListing(puneSeller, `P5 pune ${stamp}`),
    createListing(pickupOnly, `P5 pickup ${stamp}`),
    createListing(deliveryOnly, `P5 deliv ${stamp}`),
  ]);
  listingIds.push(...listings.map((item) => item.id));
  const [
    sameListing,
    mySocietyListing,
    nearbyListing,
    farNearbyListing,
    extendedListing,
    noCoordListing,
    puneListing,
    pickupListing,
    deliveryListing,
  ] = listings;

  await prisma.cityReachConfig.upsert({
    where: { cityKey: CITY_KEY },
    create: {
      cityKey: CITY_KEY,
      displayName: "Phase5 Ville",
      nearbyRadiusKm: 5,
      extendedRadiusKm: 10,
    },
    update: { nearbyRadiusKm: 5, extendedRadiusKm: 10 },
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

  const token = signToken(buyer);

  async function place(listingId, extra = {}) {
    return jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token,
      body: {
        paymentMethod: "cash",
        items: [{ listingId, quantity: 1 }],
        ...extra,
      },
    });
  }

  try {
    const same = await place(sameListing.id);
    assert(same.status === 201, `same-society order should work: ${same.status} ${JSON.stringify(same.json)}`);
    orderIds.push(same.json.id);
    assert(!same.json.fulfilmentMethod, "same-society regular order has no new fulfilment");

    const mySoc = await place(mySocietyListing.id);
    assert(mySoc.status === 400, "MY_SOCIETY other society rejected");
    assert(String(mySoc.json.error).includes("society"), "MY_SOCIETY error mentions society");

    const nearbyPickup = await place(nearbyListing.id, { fulfilmentMethod: "pickup" });
    assert(nearbyPickup.status === 201, `NEARBY within radius accepted: ${nearbyPickup.status}`);
    orderIds.push(nearbyPickup.json.id);
    assert(nearbyPickup.json.fulfilmentMethod === "pickup", "snapshots pickup");
    assert(nearbyPickup.json.deliveryCharge === 0, "pickup charge is 0");

    const nearbyDelivery = await place(nearbyListing.id, {
      fulfilmentMethod: "seller_delivery",
      deliveryCharge: 1,
      nearbyRadiusKm: 999,
    });
    assert(nearbyDelivery.status === 201, "NEARBY delivery accepted");
    orderIds.push(nearbyDelivery.json.id);
    assert(nearbyDelivery.json.fulfilmentMethod === "seller_delivery", "snapshots seller_delivery");
    assert(nearbyDelivery.json.deliveryCharge === 30, "uses current seller charge not client 1");

    const farNearby = await place(farNearbyListing.id, { fulfilmentMethod: "seller_delivery" });
    assert(farNearby.status === 400, "NEARBY outside radius rejected");

    const extended = await place(extendedListing.id, { fulfilmentMethod: "pickup" });
    assert(extended.status === 201, "EXTENDED within radius accepted");
    orderIds.push(extended.json.id);

    const pune = await place(puneListing.id, { fulfilmentMethod: "pickup" });
    assert(pune.status === 400, "different city rejected");

    const noCoord = await place(noCoordListing.id, { fulfilmentMethod: "pickup" });
    assert(noCoord.status === 400, "missing seller coordinates rejected");

    await prisma.society.update({
      where: { id: buyerSociety.id },
      data: { latitude: null, longitude: null },
    });
    const missingBuyerCoords = await place(nearbyListing.id, { fulfilmentMethod: "pickup" });
    assert(missingBuyerCoords.status === 400, "missing buyer coordinates rejected");
    await prisma.society.update({
      where: { id: buyerSociety.id },
      data: { latitude: 12.9716, longitude: 77.5946 },
    });

    await prisma.user.update({
      where: { id: nearbySeller.id },
      data: { sellingReachLevel: "MY_SOCIETY" },
    });
    const afterReach = await place(nearbyListing.id, { fulfilmentMethod: "pickup" });
    assert(afterReach.status === 400, "reach change after cart rejects order");
    await prisma.user.update({
      where: { id: nearbySeller.id },
      data: { sellingReachLevel: "NEARBY" },
    });

    await prisma.user.update({
      where: { id: nearbySeller.id },
      data: { fulfilmentMode: "BUYER_PICKUP" },
    });
    const staleFulfilment = await place(nearbyListing.id, { fulfilmentMethod: "seller_delivery" });
    assert(staleFulfilment.status === 400, "stale delivery selection rejected");
    assert(String(staleFulfilment.json.error).toLowerCase().includes("delivery option"), "fulfilment error copy");

    await prisma.user.update({
      where: { id: nearbySeller.id },
      data: { fulfilmentMode: "BOTH", deliveryCharge: 40 },
    });
    const newCharge = await place(nearbyListing.id, { fulfilmentMethod: "seller_delivery" });
    assert(newCharge.status === 201, "current charge used after profile change");
    orderIds.push(newCharge.json.id);
    assert(newCharge.json.deliveryCharge === 40, "authoritative charge is 40");

    const placedId = newCharge.json.id;
    await prisma.user.update({
      where: { id: nearbySeller.id },
      data: { fulfilmentMode: "BUYER_PICKUP", deliveryCharge: 99 },
    });
    const stored = await prisma.order.findUnique({ where: { id: placedId } });
    assert(stored.fulfilmentMethod === "seller_delivery", "historical method unchanged");
    assert(stored.deliveryCharge === 40, "historical charge unchanged");

    const pickupDelivery = await place(pickupListing.id, { fulfilmentMethod: "seller_delivery" });
    assert(pickupDelivery.status === 400, "pickup-only rejects delivery");

    const pickupOk = await place(pickupListing.id, { fulfilmentMethod: "pickup" });
    assert(pickupOk.status === 201, "pickup-only accepts pickup");
    orderIds.push(pickupOk.json.id);

    const deliveryPickup = await place(deliveryListing.id, { fulfilmentMethod: "pickup" });
    assert(deliveryPickup.status === 400, "delivery-only rejects pickup");

    const deliveryOk = await place(deliveryListing.id, { fulfilmentMethod: "seller_delivery" });
    assert(deliveryOk.status === 201, "delivery-only accepts delivery");
    orderIds.push(deliveryOk.json.id);
    assert(deliveryOk.json.deliveryCharge === 25, "delivery-only snapshots 25");

    await prisma.cityReachConfig.delete({ where: { cityKey: CITY_KEY } });
    createdCityConfig = false;
    const noConfig = await place(nearbyListing.id, { fulfilmentMethod: "pickup" });
    assert(noConfig.status === 400, "missing city config rejected");

    const seedBuyer = await prisma.user.findUnique({ where: { phone: SEED_BUYER_PHONE } });
    const seedSeller = await prisma.user.findUnique({ where: { phone: SEED_SELLER_PHONE } });
    assert(seedBuyer && seedSeller && seedBuyer.societyId === seedSeller.societyId, "seed pair same society");
    const seedListing = await prisma.listing.create({
      data: {
        sellerId: seedSeller.id,
        societyId: seedSeller.societyId,
        name: `P5 seed same ${stamp}`,
        price: 50,
        quantity: 2,
        status: "active",
      },
    });
    listingIds.push(seedListing.id);
    const seedOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: signToken(seedBuyer),
      body: {
        paymentMethod: "cash",
        items: [{ listingId: seedListing.id, quantity: 1 }],
      },
    });
    assert(seedOrder.status === 201, "existing same-society POST /orders still works");
    orderIds.push(seedOrder.json.id);

    const listingsRes = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token,
    });
    assert(listingsRes.status === 200, "listings GET works");
    assert(
      listingsRes.json.every((item) => item.societyId === buyer.societyId),
      "GET /listings remains society-scoped"
    );
  } finally {
    server.close();
    if (orderIds.length) {
      await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } });
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.orderItem.deleteMany({ where: { listingId: { in: listingIds } } }).catch(() => {});
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    if (userIds.length) {
      await prisma.refreshToken.deleteMany({ where: { userId: { in: userIds } } }).catch(() => {});
      await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    }
    if (societyIds.length) {
      await prisma.society.deleteMany({ where: { id: { in: societyIds } } });
    }
    if (createdCityConfig) {
      await prisma.cityReachConfig.delete({ where: { cityKey: CITY_KEY } }).catch(() => {});
    }
  }
}

main()
  .then(() => {
    console.log("cross-society-order tests passed");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
