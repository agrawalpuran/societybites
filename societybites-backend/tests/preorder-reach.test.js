require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const campaignRoutes = require("../routes/preorderCampaigns");
const orderRoutes = require("../routes/orders");

const CITY_KEY = "phasepreorderville";

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
      city: extras.city || "Phase Preorder Ville",
      inviteCode: `PO${Math.random().toString(36).slice(2, 10)}`,
      latitude: extras.latitude === undefined ? 12.9716 : extras.latitude,
      longitude: extras.longitude === undefined ? 77.5946 : extras.longitude,
    },
  });
}

async function createUser({ phone, societyId, role, reach, name }) {
  return prisma.user.create({
    data: {
      phone,
      name: name || phone.slice(-4),
      role: role || "seller",
      societyId,
      sellingReachLevel: reach || "MY_SOCIETY",
      fulfilmentMode: "BUYER_PICKUP",
      upiId: role === "buyer" ? null : "seller@upi",
    },
  });
}

async function createCampaign(seller, title, extras = {}) {
  const now = Date.now();
  const campaign = await prisma.preOrderCampaign.create({
    data: {
      sellerId: seller.id,
      societyId: seller.societyId,
      title,
      orderOpenAt: new Date(now - 60 * 1000),
      orderCutoffAt: new Date(now + 60 * 60 * 1000),
      fulfilmentAt: new Date(now + 2 * 60 * 60 * 1000),
      status: extras.status || "open",
    },
  });
  const listing = await prisma.listing.create({
    data: {
      sellerId: seller.id,
      societyId: seller.societyId,
      campaignId: campaign.id,
      name: extras.productName || `${title} box`,
      price: 90,
      quantity: 4,
      status: "active",
      catalogType: "PREORDER",
      inventoryMode: "demand",
      foodType: "VEG",
    },
  });
  return { campaign, listing };
}

function ids(payload) {
  return (payload || []).map((item) => item.id);
}

async function main() {
  const stamp = Date.now();
  const societyIds = [];
  const userIds = [];
  const campaignIds = [];
  const listingIds = [];
  const orderIds = [];
  let createdCityConfig = false;
  let server;

  const buyerSociety = await createSociety(`PO Buyer ${stamp}`);
  societyIds.push(buyerSociety.id);
  const nearbySociety = await createSociety(`PO Near ${stamp}`, {
    latitude: 12.9986,
    longitude: 77.5946,
  });
  societyIds.push(nearbySociety.id);
  const midSociety = await createSociety(`PO Mid ${stamp}`, {
    latitude: 13.0436,
    longitude: 77.5946,
  });
  societyIds.push(midSociety.id);
  const farSociety = await createSociety(`PO Far ${stamp}`, {
    latitude: 13.1066,
    longitude: 77.5946,
  });
  societyIds.push(farSociety.id);

  const aarav = await createUser({
    phone: `+91981${String(stamp).slice(-7)}`,
    societyId: buyerSociety.id,
    role: "seller",
    reach: "EXTENDED",
    name: "Aarav",
  });
  userIds.push(aarav.id);

  const puran = await createUser({
    phone: `+91982${String(stamp).slice(-7)}`,
    societyId: nearbySociety.id,
    role: "seller",
    reach: "EXTENDED",
    name: "Puran",
  });
  userIds.push(puran.id);

  const nearbyMySociety = await createUser({
    phone: `+91983${String(stamp).slice(-7)}`,
    societyId: nearbySociety.id,
    role: "seller",
    reach: "MY_SOCIETY",
    name: "Nearby My Society",
  });
  userIds.push(nearbyMySociety.id);

  const nearbyReach = await createUser({
    phone: `+91984${String(stamp).slice(-7)}`,
    societyId: nearbySociety.id,
    role: "seller",
    reach: "NEARBY",
    name: "Nearby Reach Cook",
  });
  userIds.push(nearbyReach.id);

  const midNearby = await createUser({
    phone: `+91985${String(stamp).slice(-7)}`,
    societyId: midSociety.id,
    role: "seller",
    reach: "NEARBY",
    name: "Mid Nearby Cook",
  });
  userIds.push(midNearby.id);

  const midExtended = await createUser({
    phone: `+91986${String(stamp).slice(-7)}`,
    societyId: midSociety.id,
    role: "seller",
    reach: "EXTENDED",
    name: "Mid Extended Cook",
  });
  userIds.push(midExtended.id);

  const farExtended = await createUser({
    phone: `+91987${String(stamp).slice(-7)}`,
    societyId: farSociety.id,
    role: "seller",
    reach: "EXTENDED",
    name: "Far Extended Cook",
  });
  userIds.push(farExtended.id);

  const aaravCamp = await createCampaign(aarav, `PO Aarav ${stamp}`);
  const puranCamp = await createCampaign(puran, `PO Puran ${stamp}`);
  const hiddenMy = await createCampaign(nearbyMySociety, `PO hidden my ${stamp}`);
  const nearbyCamp = await createCampaign(nearbyReach, `PO nearby ${stamp}`);
  const midNearbyCamp = await createCampaign(midNearby, `PO mid nearby ${stamp}`);
  const midExtCamp = await createCampaign(midExtended, `PO mid ext ${stamp}`);
  const farCamp = await createCampaign(farExtended, `PO far ${stamp}`);
  const draft = await createCampaign(puran, `PO draft ${stamp}`, { status: "draft" });

  campaignIds.push(
    aaravCamp.campaign.id,
    puranCamp.campaign.id,
    hiddenMy.campaign.id,
    nearbyCamp.campaign.id,
    midNearbyCamp.campaign.id,
    midExtCamp.campaign.id,
    farCamp.campaign.id,
    draft.campaign.id
  );
  listingIds.push(
    aaravCamp.listing.id,
    puranCamp.listing.id,
    hiddenMy.listing.id,
    nearbyCamp.listing.id,
    midNearbyCamp.listing.id,
    midExtCamp.listing.id,
    farCamp.listing.id,
    draft.listing.id
  );

  await prisma.cityReachConfig.upsert({
    where: { cityKey: CITY_KEY },
    create: {
      cityKey: CITY_KEY,
      displayName: "Phase Preorder Ville",
      nearbyRadiusKm: 5,
      extendedRadiusKm: 10,
    },
    update: { nearbyRadiusKm: 5, extendedRadiusKm: 10 },
  });
  createdCityConfig = true;

  const app = express();
  app.use(express.json());
  app.use("/preorder-campaigns", campaignRoutes);
  app.use("/orders", orderRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
      code: err.code,
    });
  });

  server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const aaravToken = signToken(aarav);
    const puranToken = signToken(puran);

    const aaravList = await jsonRequest(server, {
      method: "GET",
      path: "/preorder-campaigns",
      token: aaravToken,
    });
    assert(aaravList.status === 200, `Aarav campaign list failed: ${aaravList.status}`);
    const aaravIds = ids(aaravList.json);
    assert(aaravIds.includes(aaravCamp.campaign.id), "own campaign remains visible");
    assert(aaravIds.includes(puranCamp.campaign.id), "EXTENDED neighbor campaign visible to Aarav");
    assert(aaravIds.includes(nearbyCamp.campaign.id), "NEARBY seller campaign visible at ~3km");
    assert(aaravIds.includes(midExtCamp.campaign.id), "EXTENDED seller campaign visible at ~8km");
    assert(!aaravIds.includes(hiddenMy.campaign.id), "MY_SOCIETY seller hidden from other society");
    assert(
      !aaravIds.includes(midNearbyCamp.campaign.id),
      "NEARBY seller hidden beyond nearby radius"
    );
    assert(!aaravIds.includes(farCamp.campaign.id), "EXTENDED seller hidden beyond extended radius");
    assert(!aaravIds.includes(draft.campaign.id), "other-seller drafts stay off buyer catalog");

    const puranList = await jsonRequest(server, {
      method: "GET",
      path: "/preorder-campaigns",
      token: puranToken,
    });
    assert(puranList.status === 200, "Puran campaign list failed");
    const puranIds = ids(puranList.json);
    assert(puranIds.includes(puranCamp.campaign.id), "Puran sees own campaign");
    const puranOwn = puranList.json.find((c) => c.id === puranCamp.campaign.id);
    assert(puranOwn && puranOwn.discoveryReach === "inSociety", "own campaign stays in Your Society");
    assert(puranIds.includes(aaravCamp.campaign.id), "EXTENDED neighbor campaign visible to Puran");
    const aaravForPuran = puranList.json.find((c) => c.id === aaravCamp.campaign.id);
    assert(aaravForPuran.societyId === aarav.societyId, "Aarav campaign keeps Aarav society");
    assert(
      aaravForPuran.discoveryReach !== "inSociety",
      "Aarav campaign must not be grouped as Puran's society"
    );
    assert(aaravForPuran.sellingReachLevel === "EXTENDED", "Aarav opted into EXTENDED");
    assert(
      aaravForPuran.discoveryReach === "nearby" || aaravForPuran.discoveryReach === "extended",
      "cross-society campaign is Nearby or Extended by distance"
    );

    const visibleDetail = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${puranCamp.campaign.id}`,
      token: aaravToken,
    });
    assert(visibleDetail.status === 200, "eligible campaign detail must be 200");

    const hiddenDetail = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${hiddenMy.campaign.id}`,
      token: aaravToken,
    });
    assert(hiddenDetail.status === 404, "ineligible campaign detail must be 404");

    const farDetail = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${farCamp.campaign.id}`,
      token: aaravToken,
    });
    assert(farDetail.status === 404, "out-of-radius campaign detail must be 404");

    const ownerDrafts = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns?sellerId=${encodeURIComponent(puran.id)}`,
      token: puranToken,
    });
    assert(ownerDrafts.status === 200, "owner kitchen list failed");
    assert(
      ids(ownerDrafts.json).includes(draft.campaign.id),
      "owner still sees own draft campaigns"
    );

    const storefront = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns?sellerId=${encodeURIComponent(puran.id)}`,
      token: aaravToken,
    });
    assert(storefront.status === 200, "storefront campaign list failed");
    assert(ids(storefront.json).includes(puranCamp.campaign.id), "storefront shows eligible seller");
    assert(!ids(storefront.json).includes(draft.campaign.id), "storefront hides seller drafts");

    const order = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: aaravToken,
      body: {
        type: "pre_order",
        campaignId: puranCamp.campaign.id,
        fulfilmentMethod: "pickup",
        paymentMethod: "cash",
        items: [{ listingId: puranCamp.listing.id, quantity: 1 }],
      },
    });
    assert(order.status === 201, `cross-society pre-order failed: ${JSON.stringify(order.json)}`);
    orderIds.push(order.json.id);

    const blocked = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: aaravToken,
      body: {
        type: "pre_order",
        campaignId: hiddenMy.campaign.id,
        fulfilmentMethod: "pickup",
        paymentMethod: "cash",
        items: [{ listingId: hiddenMy.listing.id, quantity: 1 }],
      },
    });
    assert(blocked.status === 400, "MY_SOCIETY campaign must not be orderable across societies");
  } finally {
    if (server) server.close();
    if (orderIds.length) {
      await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } }).catch(() => {});
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } }).catch(() => {});
    }
    if (listingIds.length) {
      await prisma.orderItem.deleteMany({ where: { listingId: { in: listingIds } } }).catch(() => {});
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    if (campaignIds.length) {
      await prisma.preOrderCampaign.deleteMany({ where: { id: { in: campaignIds } } });
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
    console.log("preorder-reach tests passed");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
