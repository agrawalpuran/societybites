require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");

const SEED_BUYER_PHONE = "+919845154070";
const SEED_SELLER_PHONE = "+919901844776";

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
  const stamp = Date.now();
  const seller = await prisma.user.findUnique({ where: { phone: SEED_SELLER_PHONE } });
  const buyer = await prisma.user.findUnique({ where: { phone: SEED_BUYER_PHONE } });
  assert(seller && seller.societyId, "Seed seller with a society must exist");
  assert(buyer && buyer.societyId === seller.societyId, "Seed buyer must share the seller society");

  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);
  const listingIds = [];
  const orderIds = [];
  const extraUserIds = [];

  const sellerListingSnapshot = await prisma.listing.findMany({
    where: { sellerId: seller.id },
    select: {
      id: true,
      status: true,
      catalogType: true,
      availabilityMode: true,
      quantity: true,
    },
  });

  const otherSeller = await prisma.user.create({
    data: {
      phone: `+9198${String(stamp).slice(-8)}`,
      name: "Other Bulk Seller",
      role: "seller",
      societyId: seller.societyId,
    },
  });
    extraUserIds.push(otherSeller.id);

    const buyerOnly = await prisma.user.create({
      data: {
        phone: `+9197${String(stamp).slice(-8)}`,
        name: "Bulk Buyer Only",
        role: "buyer",
        societyId: seller.societyId,
      },
    });
    extraUserIds.push(buyerOnly.id);
    const buyerOnlyToken = signToken(buyerOnly);

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
    const active = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bulk active ${stamp}`,
        price: 175,
        foodType: "VEG",
        category: "Lunch",
        quantity: 8,
        catalogType: "REGULAR",
      },
    });
    assert(active.status === 201, `active create ${JSON.stringify(active.json)}`);
    listingIds.push(active.json.id);

    const paused = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bulk paused ${stamp}`,
        price: 80,
        foodType: "VEG",
        category: "Snacks",
        quantity: 5,
      },
    });
    assert(paused.status === 201, "paused candidate create");
    listingIds.push(paused.json.id);
    const pauseOne = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${paused.json.id}/pause`,
      token: sellerToken,
    });
    assert(pauseOne.status === 200, "individual pause");

    const expired = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bulk expired ${stamp}`,
        price: 175,
        foodType: "NON_VEG",
        category: "Dinner",
        quantity: 4,
      },
    });
    assert(expired.status === 201, "expired candidate create");
    listingIds.push(expired.json.id);
    await prisma.listing.update({
      where: { id: expired.json.id },
      data: {
        status: "expired",
        availableAt: new Date(Date.now() - 60 * 60 * 1000),
      },
    });

    const inactive = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bulk inactive ${stamp}`,
        price: 50,
        foodType: "VEG",
        category: "Snacks",
        quantity: 2,
      },
    });
    assert(inactive.status === 201, "inactive candidate create");
    listingIds.push(inactive.json.id);
    await prisma.listing.update({
      where: { id: inactive.json.id },
      data: { status: "inactive" },
    });

    const preorder = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Bulk preorder ${stamp}`,
        price: 220,
        foodType: "VEG",
        category: "Dinner",
        catalogType: "PREORDER",
        quantity: 10,
      },
    });
    assert(preorder.status === 201, "preorder create");
    listingIds.push(preorder.json.id);

    const otherListing = await prisma.listing.create({
      data: {
        sellerId: otherSeller.id,
        societyId: seller.societyId,
        name: `Other seller ${stamp}`,
        price: 99,
        quantity: 3,
        foodType: "VEG",
        category: "Lunch",
        status: "active",
        catalogType: "REGULAR",
      },
    });
    listingIds.push(otherListing.id);

    const existingOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: active.json.id, quantity: 1 }],
      },
    });
    assert(existingOrder.status === 201, `order create ${JSON.stringify(existingOrder.json)}`);
    orderIds.push(existingOrder.json.id);
    const orderStatusBefore = existingOrder.json.status;

    const defaultMarket = await jsonRequest(server, {
      method: "GET",
      path: `/listings?societyId=${seller.societyId}&catalogType=REGULAR`,
      token: buyerToken,
    });
    assert(defaultMarket.status === 200, "default marketplace GET");
    const defaultIds = (defaultMarket.json || []).map((row) => row.id);
    assert(defaultIds.includes(active.json.id), "active listing in default marketplace");
    assert(!defaultIds.includes(expired.json.id), "expired hidden from default status=active");
    assert(!defaultIds.includes(paused.json.id), "paused hidden from marketplace");

    const discoverable = await jsonRequest(server, {
      method: "GET",
      path: `/listings?societyId=${seller.societyId}&catalogType=REGULAR&status=discoverable`,
      token: buyerToken,
    });
    assert(discoverable.status === 200, "discoverable GET");
    const discoverableIds = (discoverable.json || []).map((row) => row.id);
    assert(discoverableIds.includes(active.json.id), "active in discoverable");
    assert(discoverableIds.includes(expired.json.id), "expired remains discoverable");
    assert(!discoverableIds.includes(paused.json.id), "paused still excluded from discoverable");
    assert(!discoverableIds.includes(inactive.json.id), "inactive excluded from discoverable");
    assert(!discoverableIds.includes(preorder.json.id), "PREORDER still separate from REGULAR");

    const vegOnly = (discoverable.json || []).filter((row) => row.foodType === "VEG");
    assert(
      vegOnly.every((row) => row.foodType === "VEG"),
      "VEG rows remain VEG"
    );
    const expiredRow = (discoverable.json || []).find((row) => row.id === expired.json.id);
    assert(expiredRow.status === "expired", "expired status preserved");
    assert(expiredRow.foodType === "NON_VEG", "foodType unchanged on expired");
    assert(expiredRow.catalogType === "REGULAR", "catalogType unchanged on expired");

    const expiredOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        societyId: seller.societyId,
        paymentMethod: "cash",
        items: [{ listingId: expired.json.id, quantity: 1 }],
      },
    });
    assert(expiredOrder.status === 400, "backend rejects ordering expired listing");

    const buyerPause = await jsonRequest(server, {
      method: "PATCH",
      path: "/listings/bulk/pause",
      token: buyerOnlyToken,
    });
    assert(
      buyerPause.status === 403,
      `buyer cannot pause all, got ${buyerPause.status} ${JSON.stringify(buyerPause.json)}`
    );

    const pauseAll = await jsonRequest(server, {
      method: "PATCH",
      path: "/listings/bulk/pause",
      token: sellerToken,
    });
    assert(pauseAll.status === 200, `pause all ${JSON.stringify(pauseAll.json)}`);
    assert(pauseAll.json.pausedCount >= 2, "pauses eligible active listings");

    const afterPause = await prisma.listing.findMany({
      where: { id: { in: listingIds } },
    });
    const byId = Object.fromEntries(afterPause.map((row) => [row.id, row]));
    assert(byId[active.json.id].status === "paused", "active listing paused");
    assert(byId[paused.json.id].status === "paused", "already paused stays paused");
    assert(byId[expired.json.id].status === "expired", "expired not converted");
    assert(byId[inactive.json.id].status === "inactive", "inactive not revived or paused");
    assert(byId[preorder.json.id].status === "paused", "own PREORDER can be paused");
    assert(byId[preorder.json.id].catalogType === "PREORDER", "catalogType untouched");
    assert(byId[otherListing.id].status === "active", "other seller listing untouched");
    assert(byId[active.json.id].availabilityMode === "READY_NOW", "availabilityMode untouched");
    assert(byId[active.json.id].price === 175, "price untouched");

    const orderAfter = await prisma.order.findUnique({ where: { id: existingOrder.json.id } });
    assert(orderAfter.status === orderStatusBefore, "existing order status untouched");

    const pauseAgain = await jsonRequest(server, {
      method: "PATCH",
      path: "/listings/bulk/pause",
      token: sellerToken,
    });
    assert(pauseAgain.status === 400, "no eligible listings to pause");

    const resumeAll = await jsonRequest(server, {
      method: "PATCH",
      path: "/listings/bulk/resume",
      token: sellerToken,
    });
    assert(resumeAll.status === 200, `resume all ${JSON.stringify(resumeAll.json)}`);
    assert(resumeAll.json.resumedCount >= 2, "resumes paused listings");

    const afterResume = await prisma.listing.findMany({
      where: { id: { in: listingIds } },
    });
    const resumedById = Object.fromEntries(afterResume.map((row) => [row.id, row]));
    assert(resumedById[active.json.id].status === "active", "paused listing renewed");
    assert(resumedById[paused.json.id].status === "active", "previously paused listing renewed");
    assert(resumedById[expired.json.id].status === "expired", "expired not revived by Renew All");
    assert(resumedById[inactive.json.id].status === "inactive", "inactive not revived");
    assert(resumedById[preorder.json.id].status === "active", "paused preorder resumed");
    assert(resumedById[preorder.json.id].catalogType === "PREORDER", "preorder catalog unchanged");
    assert(resumedById[otherListing.id].status === "active", "other seller still untouched");

    const resumeAgain = await jsonRequest(server, {
      method: "PATCH",
      path: "/listings/bulk/resume",
      token: sellerToken,
    });
    assert(resumeAgain.status === 400, "no paused listings to renew");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (orderIds.length) {
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
    for (const row of sellerListingSnapshot) {
      if (listingIds.includes(row.id)) continue;
      await prisma.listing.update({
        where: { id: row.id },
        data: {
          status: row.status,
          catalogType: row.catalogType,
          availabilityMode: row.availabilityMode,
          quantity: row.quantity,
        },
      });
    }
    if (extraUserIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: extraUserIds } } });
    }
    await prisma.$disconnect();
  }
}

main()
  .then(() => {
    console.log("listing-bulk-expiry tests passed");
    process.exit(0);
  })
  .catch(async (err) => {
    console.error(err);
    await prisma.$disconnect();
    process.exit(1);
  });
