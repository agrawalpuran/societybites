require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { evaluateSellerDiscoveryEligibility, discoveryDisplayReach } = require("../lib/sellingReachEligibility");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_SOCIETY_ID = "brigade-gateway";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function society(id, extras = {}) {
  return {
    id,
    city: "Bengaluru",
    latitude: 12.9716,
    longitude: 77.5946,
    ...extras,
  };
}

const bengaluruConfig = { cityKey: "bengaluru", nearbyRadiusKm: 5, extendedRadiusKm: 10 };

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

function mainUnit() {
  const a = society("society-a");
  // ~3 km north of 12.9716 — inside 5 km Nearby.
  const nearbyInside = society("society-b", { latitude: 12.9986, longitude: 77.5946 });
  // ~8 km north — outside Nearby, inside Extended 10 km.
  const nearbyOutside = society("society-c", { latitude: 13.0436, longitude: 77.5946 });
  // ~15 km north — outside Extended.
  const extendedOutside = society("society-d", { latitude: 13.1066, longitude: 77.5946 });
  const pune = society("society-pune", { city: "Pune", latitude: 18.52, longitude: 73.85 });

  const sameMine = evaluateSellerDiscoveryEligibility({
    buyerSociety: a,
    sellerSociety: a,
    sellingReachLevel: "MY_SOCIETY",
    cityReachConfig: bengaluruConfig,
  });
  assert(sameMine.eligible === true, "same society + MY_SOCIETY eligible");

  const closeButMine = evaluateSellerDiscoveryEligibility({
    buyerSociety: nearbyInside,
    sellerSociety: a,
    sellingReachLevel: "MY_SOCIETY",
    cityReachConfig: bengaluruConfig,
  });
  assert(closeButMine.eligible === false, "different society + MY_SOCIETY not eligible even if close");
  assert(closeButMine.reason === "MY_SOCIETY_ONLY", "MY_SOCIETY reason");

  const nearbyYes = evaluateSellerDiscoveryEligibility({
    buyerSociety: nearbyInside,
    sellerSociety: a,
    sellingReachLevel: "NEARBY",
    cityReachConfig: bengaluruConfig,
    nearbyRadiusKm: 999,
    distanceKm: 0,
  });
  assert(nearbyYes.eligible === true, "NEARBY inside radius eligible");
  assert(nearbyYes.appliedRadiusKm === 5, "client radius must be ignored; city config used");
  assert(nearbyYes.distanceKm != null && nearbyYes.distanceKm <= 5, "distance within nearby");

  const nearbyNo = evaluateSellerDiscoveryEligibility({
    buyerSociety: nearbyOutside,
    sellerSociety: a,
    sellingReachLevel: "NEARBY",
    cityReachConfig: bengaluruConfig,
  });
  assert(nearbyNo.eligible === false, "NEARBY outside radius not eligible");

  const extendedYes = evaluateSellerDiscoveryEligibility({
    buyerSociety: nearbyOutside,
    sellerSociety: a,
    sellingReachLevel: "EXTENDED",
    cityReachConfig: bengaluruConfig,
  });
  assert(extendedYes.eligible === true, "EXTENDED inside extended radius eligible");
  assert(extendedYes.appliedRadiusKm === 10, "extended uses city extendedRadiusKm");
  assert(
    discoveryDisplayReach(sameMine, 5) === "inSociety",
    "same society campaigns group in society"
  );
  assert(
    discoveryDisplayReach(nearbyYes, 5) === "nearby",
    "within nearby radius groups as nearby"
  );
  assert(
    discoveryDisplayReach(extendedYes, 5) === "extended",
    "outside nearby and inside extended groups as extended"
  );

  const extendedNo = evaluateSellerDiscoveryEligibility({
    buyerSociety: extendedOutside,
    sellerSociety: a,
    sellingReachLevel: "EXTENDED",
    cityReachConfig: bengaluruConfig,
  });
  assert(extendedNo.eligible === false, "EXTENDED outside radius not eligible");

  const noConfig = evaluateSellerDiscoveryEligibility({
    buyerSociety: nearbyInside,
    sellerSociety: a,
    sellingReachLevel: "NEARBY",
    cityReachConfig: null,
  });
  assert(noConfig.eligible === false, "missing city config not eligible");
  assert(noConfig.reason === "CITY_CONFIG_MISSING", "missing config reason");

  const sellerNoCoords = evaluateSellerDiscoveryEligibility({
    buyerSociety: nearbyInside,
    sellerSociety: society("society-a", { latitude: null, longitude: null }),
    sellingReachLevel: "NEARBY",
    cityReachConfig: bengaluruConfig,
  });
  assert(sellerNoCoords.eligible === false, "missing seller coordinates not eligible");
  assert(sellerNoCoords.reason === "SELLER_COORDINATES_MISSING", "seller coords reason");

  const buyerNoCoords = evaluateSellerDiscoveryEligibility({
    buyerSociety: society("society-b", { latitude: null, longitude: null }),
    sellerSociety: a,
    sellingReachLevel: "NEARBY",
    cityReachConfig: bengaluruConfig,
  });
  assert(buyerNoCoords.eligible === false, "missing buyer coordinates not eligible");
  assert(buyerNoCoords.reason === "BUYER_COORDINATES_MISSING", "buyer coords reason");

  const crossCity = evaluateSellerDiscoveryEligibility({
    buyerSociety: pune,
    sellerSociety: a,
    sellingReachLevel: "EXTENDED",
    cityReachConfig: bengaluruConfig,
  });
  assert(crossCity.eligible === false, "different cities not eligible");
  assert(crossCity.reason === "DIFFERENT_CITY", "cross-city reason");

  const bangaloreAlias = evaluateSellerDiscoveryEligibility({
    buyerSociety: society("society-b", { city: "Bangalore", latitude: 12.9986, longitude: 77.5946 }),
    sellerSociety: society("society-a", { city: "Bengaluru" }),
    sellingReachLevel: "NEARBY",
    cityReachConfig: { cityKey: "bengaluru", nearbyRadiusKm: 5, extendedRadiusKm: 10 },
  });
  assert(bangaloreAlias.eligible === true, "Bangalore/Bengaluru are the same city");
}

async function mainHttp() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "seed buyer and seller required");
  assert(buyer.societyId !== OTHER_SOCIETY_ID, "seed buyer must not be other society");

  const app = express();
  app.use(express.json());
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
    const otherListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: OTHER_SOCIETY_ID,
        name: `Eligibility other-society ${Date.now()}`,
        price: 80,
        quantity: 1,
        status: "active",
      },
    });
    listingIds.push(otherListing.id);

    const token = signToken(buyer);
    const listings = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token,
    });
    assert(listings.status === 200, "GET /listings failed");
    assert(
      listings.json.every((item) => item.societyId === buyer.societyId),
      "GET /listings remains society-scoped"
    );
    assert(
      !listings.json.some((item) => item.id === otherListing.id),
      "other-society listing hidden from catalog"
    );

    const detail = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${otherListing.id}`,
      token,
    });
    assert(detail.status === 404, "GET /listings/:id remains society-scoped");

    const order = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: otherListing.id, quantity: 1 }],
      },
    });
    assert(order.status === 400, "POST /orders remains society-scoped");
  } finally {
    await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    await new Promise((resolve) => server.close(resolve));
  }
}

mainUnit();
mainHttp()
  .then(() => {
    console.log("selling-reach-eligibility tests passed");
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
