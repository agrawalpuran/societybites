require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { canonicalCityKey } = require("../lib/launchCity");
const {
  validateCityReachRadii,
  serializeSellingReach,
  DEFAULT_SELLING_REACH_LEVEL,
} = require("../lib/sellingReach");
const authRoutes = require("../routes/auth");
const listingRoutes = require("../routes/listings");
const campaignRoutes = require("../routes/preorderCampaigns");
const orderRoutes = require("../routes/orders");
const adminRoutes = require("../routes/admin");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OTHER_SOCIETY_ID = "brigade-gateway";
const TEST_CITY_KEY_SOURCE = "Phase1ReachTestCity";
const ADMIN_PHONE = "+919800000091";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function expectThrow(fn, statusCode, snippet) {
  try {
    fn();
    throw new Error("expected an error");
  } catch (err) {
    if (err.message === "expected an error") throw err;
    assert(err.statusCode === statusCode, `status ${err.statusCode} != ${statusCode}`);
    assert(
      String(err.message).includes(snippet),
      `message "${err.message}" did not include "${snippet}"`
    );
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
  expectThrow(() => validateCityReachRadii({ nearbyRadiusKm: 0, extendedRadiusKm: 10 }), 400, "greater than 0");
  expectThrow(() => validateCityReachRadii({ nearbyRadiusKm: -1, extendedRadiusKm: 10 }), 400, "greater than 0");
  expectThrow(
    () => validateCityReachRadii({ nearbyRadiusKm: 5, extendedRadiusKm: 5 }),
    400,
    "greater than nearbyRadiusKm"
  );
  expectThrow(
    () => validateCityReachRadii({ nearbyRadiusKm: 8, extendedRadiusKm: 3 }),
    400,
    "greater than nearbyRadiusKm"
  );

  assert(canonicalCityKey("Bangalore") === "bengaluru", "Bangalore must canonicalize to bengaluru");
  assert(canonicalCityKey("Bengaluru") === "bengaluru", "Bengaluru must canonicalize to bengaluru");
  assert(
    canonicalCityKey("Bangalore") === canonicalCityKey("Bengaluru"),
    "Bangalore and Bengaluru must share a cityKey"
  );

  const missingReach = serializeSellingReach("Bangalore", null);
  assert(missingReach.cityKey === "bengaluru", "missing config still resolves cityKey");
  assert(missingReach.nearbyRadiusKm === null, "missing config nearby is null");
  assert(missingReach.extendedRadiusKm === null, "missing config extended is null");

  const buyer = await prisma.user.findUnique({
    where: { phone: BUYER_PHONE },
    include: { society: true },
  });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && buyer.societyId, "Seed buyer with a society must exist");
  assert(seller && seller.societyId, "Seed seller must exist");
  assert(buyer.societyId !== OTHER_SOCIETY_ID, "Seed buyer must not belong to the other test society");

  const originalBuyerSocietyId = buyer.societyId;
  const originalBuyerReach = buyer.sellingReachLevel;
  const originalSellerReach = seller.sellingReachLevel;

  const newUser = await prisma.user.create({
    data: {
      phone: `+9198${String(Date.now()).slice(-8)}`,
      role: "buyer",
    },
  });
  const reachBuyer = await prisma.user.create({
    data: {
      phone: `+9198${String(Date.now() + 1).slice(-8)}`,
      role: "buyer",
      societyId: buyer.societyId,
    },
  });
  assert(
    newUser.sellingReachLevel === DEFAULT_SELLING_REACH_LEVEL,
    "new user must default to MY_SOCIETY"
  );

  const buyerAfterCreate = await prisma.user.findUnique({ where: { id: buyer.id } });
  assert(
    buyerAfterCreate.societyId === originalBuyerSocietyId,
    "existing user society must be unchanged"
  );
  assert(
    buyerAfterCreate.sellingReachLevel === originalBuyerReach ||
      buyerAfterCreate.sellingReachLevel === DEFAULT_SELLING_REACH_LEVEL,
    "existing user reach must remain MY_SOCIETY (or their stored value)"
  );
  assert(
    newUser.sellingReachLevel === "MY_SOCIETY",
    "new users must automatically be MY_SOCIETY"
  );

  await prisma.user.update({
    where: { id: seller.id },
    data: { sellingReachLevel: "MY_SOCIETY" },
  });
  seller.sellingReachLevel = "MY_SOCIETY";

  const otherSociety = await prisma.society.findUnique({ where: { id: OTHER_SOCIETY_ID } });
  assert(otherSociety, `Society ${OTHER_SOCIETY_ID} must exist from seed`);

  const admin = await prisma.user.upsert({
    where: { phone: ADMIN_PHONE },
    update: { role: "super_admin", suspended: false },
    create: { phone: ADMIN_PHONE, name: "Reach Test Admin", role: "super_admin" },
  });

  const buyerToken = signToken(buyer);
  const reachBuyerToken = signToken(reachBuyer);
  const sellerToken = signToken(seller);
  const adminToken = signToken(admin);
  const created = { listingIds: [], userIds: [newUser.id, reachBuyer.id], cityKeys: [] };

  const savedBengaluru = await prisma.cityReachConfig.findUnique({
    where: { cityKey: "bengaluru" },
  });

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/listings", listingRoutes);
  app.use("/preorder-campaigns", campaignRoutes);
  app.use("/orders", orderRoutes);
  app.use("/admin", adminRoutes);
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
    await prisma.cityReachConfig.deleteMany({ where: { cityKey: "bengaluru" } });

    const meMissing = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me",
      token: buyerToken,
    });
    assert(meMissing.status === 200, `GET /auth/me failed: ${meMissing.status} ${JSON.stringify(meMissing.json)}`);
    assert(meMissing.json.sellingReachLevel, "GET /me must return sellingReachLevel");
    assert(meMissing.json.id === buyer.id, "GET /me contract must still include user id");
    assert(meMissing.json.phone === buyer.phone, "GET /me contract must still include phone");
    assert(meMissing.json.societyId === buyer.societyId, "GET /me contract must still include societyId");
    assert(meMissing.json.sellingReach, "GET /me must include sellingReach");
    assert(
      meMissing.json.sellingReach.cityKey === canonicalCityKey(buyer.society.city),
      "GET /me must resolve the canonical city from society.city"
    );
    assert(meMissing.json.sellingReach.cityKey === "bengaluru", "Bangalore society city must resolve to bengaluru");
    assert(meMissing.json.sellingReach.nearbyRadiusKm === null, "missing CityReachConfig nearby is null");
    assert(meMissing.json.sellingReach.extendedRadiusKm === null, "missing CityReachConfig extended is null");

    assert(seller.sellingReachLevel === "MY_SOCIETY", "seller defaults to MY_SOCIETY");

    const sellerKeepMine = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { sellingReachLevel: "MY_SOCIETY" },
    });
    assert(sellerKeepMine.status === 200, "seller can save MY_SOCIETY");
    assert(sellerKeepMine.json.user.sellingReachLevel === "MY_SOCIETY", "seller MY_SOCIETY persisted");

    const sellerNearbyMissing = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { sellingReachLevel: "NEARBY" },
    });
    assert(sellerNearbyMissing.status === 400, "NEARBY rejected when city config is missing");

    const sellerExtendedMissing = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { sellingReachLevel: "EXTENDED" },
    });
    assert(sellerExtendedMissing.status === 400, "EXTENDED rejected when city config is missing");

    const invalidLevel = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { sellingReachLevel: "CITYWIDE" },
    });
    assert(invalidLevel.status === 400, "invalid sellingReachLevel rejected");

    const rejectNearby = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: reachBuyerToken,
      body: { sellingReachLevel: "NEARBY" },
    });
    assert(rejectNearby.status === 400, "non-seller cannot enable seller reach");
    const rejectExtended = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: reachBuyerToken,
      body: { sellingReachLevel: "EXTENDED" },
    });
    assert(rejectExtended.status === 400, "non-seller cannot enable EXTENDED");
    const keepMine = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: buyerToken,
      body: { sellingReachLevel: "MY_SOCIETY" },
    });
    assert(keepMine.status === 200, "MY_SOCIETY profile patch must succeed");

    const forbidden = await jsonRequest(server, {
      method: "PUT",
      path: `/admin/city-reach-configs/${encodeURIComponent("Bangalore")}`,
      token: buyerToken,
      body: { nearbyRadiusKm: 5, extendedRadiusKm: 10, displayName: "Bengaluru" },
    });
    assert(forbidden.status === 403, "non-admin cannot modify city reach configuration");

    const invalidNearby = await jsonRequest(server, {
      method: "PUT",
      path: `/admin/city-reach-configs/${encodeURIComponent(TEST_CITY_KEY_SOURCE)}`,
      token: adminToken,
      body: { nearbyRadiusKm: 0, extendedRadiusKm: 10 },
    });
    assert(invalidNearby.status === 400, "invalid nearbyRadiusKm must be rejected");

    const invalidExtended = await jsonRequest(server, {
      method: "PUT",
      path: `/admin/city-reach-configs/${encodeURIComponent(TEST_CITY_KEY_SOURCE)}`,
      token: adminToken,
      body: { nearbyRadiusKm: 8, extendedRadiusKm: 3 },
    });
    assert(invalidExtended.status === 400, "extendedRadiusKm <= nearby must be rejected");

    const createdConfig = await jsonRequest(server, {
      method: "PUT",
      path: `/admin/city-reach-configs/${encodeURIComponent("Bangalore")}`,
      token: adminToken,
      body: { nearbyRadiusKm: 5, extendedRadiusKm: 10, displayName: "Bengaluru" },
    });
    assert(createdConfig.status === 200, `admin create failed: ${createdConfig.status} ${JSON.stringify(createdConfig.json)}`);
    assert(createdConfig.json.cityKey === "bengaluru", "admin PUT must canonicalize cityKey");
    assert(createdConfig.json.nearbyRadiusKm === 5, "admin nearby radius stored");
    assert(createdConfig.json.extendedRadiusKm === 10, "admin extended radius stored");
    created.cityKeys.push("bengaluru");

    const aliasUpdate = await jsonRequest(server, {
      method: "PUT",
      path: `/admin/city-reach-configs/${encodeURIComponent("Bengaluru")}`,
      token: adminToken,
      body: { nearbyRadiusKm: 6, extendedRadiusKm: 12, displayName: "Bengaluru" },
    });
    assert(aliasUpdate.status === 200, "alias PUT must update the same city row");
    assert(aliasUpdate.json.cityKey === "bengaluru", "Bengaluru PUT must not create a duplicate city");
    assert(aliasUpdate.json.nearbyRadiusKm === 6, "alias update nearby");

    const listed = await jsonRequest(server, {
      method: "GET",
      path: "/admin/city-reach-configs",
      token: adminToken,
    });
    assert(listed.status === 200, "admin GET city-reach-configs failed");
    const bengaluruRows = listed.json.filter((row) => row.cityKey === "bengaluru");
    assert(bengaluruRows.length === 1, "Bangalore/Bengaluru must not create duplicate configs");

    const meResolved = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me",
      token: buyerToken,
    });
    assert(meResolved.json.sellingReach.cityKey === "bengaluru", "GET /me cityKey after config");
    assert(meResolved.json.sellingReach.nearbyRadiusKm === 6, "GET /me nearby from CityReachConfig");
    assert(meResolved.json.sellingReach.extendedRadiusKm === 12, "GET /me extended from CityReachConfig");

    const sellerNearby = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { sellingReachLevel: "NEARBY", nearbyRadiusKm: 99, extendedRadiusKm: 1 },
    });
    assert(sellerNearby.status === 200, `seller NEARBY failed: ${JSON.stringify(sellerNearby.json)}`);
    assert(sellerNearby.json.user.sellingReachLevel === "NEARBY", "seller can save NEARBY when config exists");
    assert(sellerNearby.json.user.nearbyRadiusKm == null, "client radius must not be stored on the user");
    assert(sellerNearby.json.user.sellingReach.nearbyRadiusKm === 6, "saved reach still uses city config");

    const sellerExtended = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { sellingReachLevel: "EXTENDED" },
    });
    assert(sellerExtended.status === 200, "seller can save EXTENDED when config exists");
    assert(sellerExtended.json.user.sellingReachLevel === "EXTENDED", "EXTENDED persisted");

    const buyerStillBlocked = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: reachBuyerToken,
      body: { sellingReachLevel: "NEARBY" },
    });
    assert(buyerStillBlocked.status === 400, "buyer cannot enable NEARBY even when config exists");

    const configUnchanged = await prisma.cityReachConfig.findUnique({ where: { cityKey: "bengaluru" } });
    assert(configUnchanged.nearbyRadiusKm === 6, "client radius must not change CityReachConfig");
    assert(configUnchanged.extendedRadiusKm === 12, "client radius must not change CityReachConfig");

    const otherListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: OTHER_SOCIETY_ID,
        name: `Reach other-society ${Date.now()}`,
        price: 99,
        quantity: 1,
        status: "active",
      },
    });
    created.listingIds.push(otherListing.id);

    const listings = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token: buyerToken,
    });
    assert(listings.status === 200, "GET /listings failed");
    assert(
      listings.json.every((item) => item.societyId === buyer.societyId),
      "GET /listings must remain society-scoped"
    );
    assert(
      !listings.json.some((item) => item.id === otherListing.id),
      "GET /listings must not include another society's listing"
    );

    const otherDetail = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${otherListing.id}`,
      token: buyerToken,
    });
    assert(otherDetail.status === 404, "GET /listings/:id must hide other-society listings");

    const campaigns = await jsonRequest(server, {
      method: "GET",
      path: "/preorder-campaigns",
      token: buyerToken,
    });
    assert(campaigns.status === 200, "GET /preorder-campaigns failed");
    assert(Array.isArray(campaigns.json), "GET /preorder-campaigns must return a list");

    const crossOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: otherListing.id, quantity: 1 }],
      },
    });
    assert(crossOrder.status === 400, "POST /orders must reject cross-society listings");
    assert(
      String(crossOrder.json && crossOrder.json.error).includes("society"),
      "cross-society order error must mention society"
    );
  } finally {
    await prisma.user.update({
      where: { id: seller.id },
      data: { sellingReachLevel: originalSellerReach || "MY_SOCIETY" },
    });
    await prisma.listing.deleteMany({ where: { id: { in: created.listingIds } } });
    await prisma.user.deleteMany({ where: { id: { in: created.userIds } } });
    await prisma.auditLog.deleteMany({ where: { adminId: admin.id } });
    await prisma.user.deleteMany({ where: { id: admin.id } });

    if (savedBengaluru) {
      await prisma.cityReachConfig.upsert({
        where: { cityKey: "bengaluru" },
        update: {
          displayName: savedBengaluru.displayName,
          nearbyRadiusKm: savedBengaluru.nearbyRadiusKm,
          extendedRadiusKm: savedBengaluru.extendedRadiusKm,
        },
        create: {
          cityKey: savedBengaluru.cityKey,
          displayName: savedBengaluru.displayName,
          nearbyRadiusKm: savedBengaluru.nearbyRadiusKm,
          extendedRadiusKm: savedBengaluru.extendedRadiusKm,
        },
      });
    } else {
      await prisma.cityReachConfig.deleteMany({ where: { cityKey: "bengaluru" } });
    }

    await new Promise((resolve) => server.close(resolve));
  }
}

main()
  .then(() => {
    console.log("selling-reach tests passed");
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
