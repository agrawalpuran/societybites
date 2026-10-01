require("dotenv").config();
const assert = require("assert");
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");
const {
  recentPastCutoff,
  parseScope,
  RECENT_PAST_DAYS,
} = require("../lib/sellerOrderList");
const { formatIstYmd, addDaysYmd, startOfIstDay } = require("../lib/sellerInsights");

const BUYER_PHONE = "+919111000071";
const SELLER_PHONE = "+919111000070";
const SEED_SELLER_PHONE = "+919901844776";

function assertCond(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const request = http.request(
      {
        hostname: "127.0.0.1",
        port: address.port,
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
      (response) => {
        let data = "";
        response.on("data", (chunk) => (data += chunk));
        response.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {}
          resolve({ status: response.statusCode, json });
        });
      }
    );
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

const cutoff = recentPastCutoff(new Date("2026-09-27T10:00:00.000+05:30"));
assertCond(
  cutoff.toISOString() === startOfIstDay(addDaysYmd("2026-09-27", -6)).toISOString(),
  "Sep 27 recent window starts Sep 21 IST"
);
assertCond(formatIstYmd(cutoff) === "2026-09-21", "cutoff date is Sep 21 IST");
assertCond(RECENT_PAST_DAYS === 7, "window is 7 inclusive calendar days");

try {
  parseScope("past");
  throw new Error("invalid scope must throw");
} catch (err) {
  assertCond(err.statusCode === 400, "invalid scope is 400");
}
assertCond(parseScope("active") === "active", "active scope accepted");
assertCond(parseScope("recent_past") === "recent_past", "recent_past accepted");
assertCond(parseScope("older") === "older", "older accepted");

async function main() {
  const seedSeller = await prisma.user.findUnique({
    where: { phone: SEED_SELLER_PHONE },
  });
  assertCond(seedSeller, "Seed seller must exist for society");

  const seller = await prisma.user.upsert({
    where: { phone: SELLER_PHONE },
    update: {
      name: "History Seller",
      role: "seller",
      societyId: seedSeller.societyId,
      suspended: false,
    },
    create: {
      phone: SELLER_PHONE,
      name: "History Seller",
      role: "seller",
      societyId: seedSeller.societyId,
    },
  });
  const buyer = await prisma.user.upsert({
    where: { phone: BUYER_PHONE },
    update: {
      name: "History Buyer",
      role: "buyer",
      societyId: seedSeller.societyId,
      suspended: false,
    },
    create: {
      phone: BUYER_PHONE,
      name: "History Buyer",
      role: "buyer",
      societyId: seedSeller.societyId,
    },
  });

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);

  const app = express();
  app.use(express.json());
  app.use("/orders", orderRoutes);
  app.use((error, _req, res, _next) => {
    const statusCode = error.statusCode || 500;
    res
      .status(statusCode)
      .json({ error: statusCode === 500 ? "Internal server error" : error.message });
  });

  const server = await new Promise((resolve) => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
  });

  const listingIds = [];
  const orderIds = [];

  try {
    const listing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `History ${Date.now()}`,
        price: 60,
        quantity: 40,
        status: "active",
      },
    });
    listingIds.push(listing.id);

    async function placeCash() {
      const created = await jsonRequest(server, {
        method: "POST",
        path: "/orders",
        token: buyerToken,
        body: {
          paymentMethod: "cash",
          items: [{ listingId: listing.id, quantity: 1 }],
        },
      });
      assertCond(created.status === 201, `create failed ${JSON.stringify(created.json)}`);
      orderIds.push(created.json.id);
      return created.json;
    }

    async function markCompleted(orderId, when) {
      await prisma.order.update({
        where: { id: orderId },
        data: {
          status: "completed",
          paymentStatus: "paid",
          completedAt: when,
          createdAt: when,
          updatedAt: when,
        },
      });
    }

    const activeOld = await placeCash();
    const recentDone = await placeCash();
    const fiveDay = await placeCash();
    const tenDay = await placeCash();
    const extras = [];
    for (let i = 0; i < 3; i += 1) extras.push(await placeCash());

    const now = Date.now();
    await prisma.order.update({
      where: { id: activeOld.id },
      data: { createdAt: new Date(now - 10 * 24 * 60 * 60 * 1000) },
    });
    await markCompleted(recentDone.id, new Date(now));
    await markCompleted(fiveDay.id, new Date(now - 5 * 24 * 60 * 60 * 1000));
    await markCompleted(tenDay.id, new Date(now - 10 * 24 * 60 * 60 * 1000));
    for (let i = 0; i < extras.length; i += 1) {
      await markCompleted(
        extras[i].id,
        new Date(now - (11 + i) * 24 * 60 * 60 * 1000)
      );
    }

    const unscoped = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller",
      token: sellerToken,
    });
    assertCond(unscoped.status === 200, "unscoped seller list still works");
    assertCond(Array.isArray(unscoped.json), "unscoped seller list remains an array");

    const buyerList = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=buyer",
      token: buyerToken,
    });
    assertCond(Array.isArray(buyerList.json), "buyer list remains an array");

    const badScope = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=history",
      token: sellerToken,
    });
    assertCond(badScope.status === 400, "invalid scope rejected");

    const active = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=active",
      token: sellerToken,
    });
    assertCond(active.status === 200, "active scope ok");
    const activeIds = active.json.orders.map((o) => o.id);
    assertCond(!activeIds.includes(activeOld.id), "10-day open order is not default Active");
    assertCond(active.json.hasOlder === true, "hasOlder when older open orders exist");
    assertCond(
      active.json.pendingCount >= 1,
      "attention badge still counts older orders needing action"
    );
    assertCond(!activeIds.includes(tenDay.id), "completed is not active");

    const olderActive = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=older_active",
      token: sellerToken,
    });
    assertCond(olderActive.status === 200, "older_active scope ok");
    const olderActiveIds = olderActive.json.orders.map((o) => o.id);
    assertCond(olderActiveIds.includes(activeOld.id), "10-day pending loads in older active");
    assertCond(!olderActiveIds.includes(tenDay.id), "completed is not older active");

    const recent = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=recent_past",
      token: sellerToken,
    });
    assertCond(recent.status === 200, "recent_past ok");
    const recentIds = recent.json.orders.map((o) => o.id);
    assertCond(recentIds.includes(recentDone.id), "completed today is recent past");
    assertCond(recentIds.includes(fiveDay.id), "completed 5 days ago is recent past");
    assertCond(!recentIds.includes(tenDay.id), "completed 10 days ago is not default past");
    assertCond(recent.json.hasOlder === true, "hasOlder when older history exists");

    const older = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=older&limit=2&page=1",
      token: sellerToken,
    });
    assertCond(older.status === 200, "older scope ok");
    const olderIds = older.json.orders.map((o) => o.id);
    assertCond(older.json.orders.length <= 2, "older page respects limit");
    assertCond(older.json.hasMore === true, "more than 2 older orders paginates");
    assertCond(!olderIds.includes(recentDone.id), "recent past is not in older page");
    assertCond(!olderIds.includes(activeOld.id), "active is not in older page");

    const page2 = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=older&limit=2&page=2",
      token: sellerToken,
    });
    assertCond(page2.status === 200, "older page 2 ok");
    const page2Ids = page2.json.orders.map((o) => o.id);
    for (const id of page2Ids) {
      assertCond(!olderIds.includes(id), "page 2 does not repeat page 1");
    }
    const pagedOlderIds = [...olderIds, ...page2Ids];
    assertCond(
      pagedOlderIds.includes(tenDay.id),
      "completed 10 days ago loads in Older Orders"
    );

    const buyerScoped = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=buyer&scope=older",
      token: buyerToken,
    });
    assertCond(Array.isArray(buyerScoped.json), "buyer ignores seller scope and stays an array");

    console.log("seller-order-history.test.js passed");
  } finally {
    await server.close();
    if (orderIds.length) {
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
