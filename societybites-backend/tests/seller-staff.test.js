require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const authRoutes = require("../routes/auth");
const orderRoutes = require("../routes/orders");
const sellerStaffRoutes = require("../routes/sellerStaff");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const OWNER_PHONE = "+919111000041";
const STRANGER_PHONE = "+919111000042";

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
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");
  assert(seller.role === "seller", "Seed seller must have seller role");

  const owner = await prisma.user.upsert({
    where: { phone: OWNER_PHONE },
    update: {
      name: "Staff Owner Viewer",
      role: "buyer",
      societyId: buyer.societyId,
      suspended: false,
    },
    create: {
      phone: OWNER_PHONE,
      name: "Staff Owner Viewer",
      role: "buyer",
      societyId: buyer.societyId,
    },
  });

  const stranger = await prisma.user.upsert({
    where: { phone: STRANGER_PHONE },
    update: {
      name: "Staff Stranger",
      role: "buyer",
      societyId: buyer.societyId,
      suspended: false,
    },
    create: {
      phone: STRANGER_PHONE,
      name: "Staff Stranger",
      role: "buyer",
      societyId: buyer.societyId,
    },
  });

  await prisma.sellerStaffMembership.deleteMany({
    where: {
      OR: [
        { sellerUserId: seller.id, staffUserId: owner.id },
        { sellerUserId: seller.id, staffUserId: stranger.id },
        { staffUserId: owner.id },
      ],
    },
  });

  const sellerToken = signToken(seller);
  const ownerToken = signToken(owner);
  const strangerToken = signToken(stranger);
  const buyerToken = signToken(buyer);

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/orders", orderRoutes);
  app.use("/seller-staff", sellerStaffRoutes);
  app.use((error, _req, res, _next) => {
    const statusCode = error.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : error.message,
      code: error.code,
    });
  });

  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  try {
    const buyerInvite = await jsonRequest(server, {
      method: "POST",
      path: "/seller-staff/owners/invite",
      token: buyerToken,
      body: { phone: OWNER_PHONE },
    });
    assert(buyerInvite.status === 403, "buyer cannot invite owner");

    const invite = await jsonRequest(server, {
      method: "POST",
      path: "/seller-staff/owners/invite",
      token: sellerToken,
      body: { phone: OWNER_PHONE },
    });
    assert(invite.status === 201, `invite owner: ${invite.status} ${JSON.stringify(invite.json)}`);
    assert(invite.json.membership?.role === "owner", "membership role owner");
    assert(invite.json.membership?.viewOnly === true, "owner is view-only");
    assert(invite.json.membership?.staffUserId === owner.id, "staff user matched");

    const dup = await jsonRequest(server, {
      method: "POST",
      path: "/seller-staff/owners/invite",
      token: sellerToken,
      body: { phone: OWNER_PHONE },
    });
    assert(dup.status === 409, "duplicate invite is 409");

    const selfInvite = await jsonRequest(server, {
      method: "POST",
      path: "/seller-staff/owners/invite",
      token: sellerToken,
      body: { phone: SELLER_PHONE },
    });
    assert(selfInvite.status === 400, "cannot invite own number");

    const owners = await jsonRequest(server, {
      method: "GET",
      path: "/seller-staff/owners",
      token: sellerToken,
    });
    assert(owners.status === 200, "list owners");
    assert(
      owners.json.owners.some((row) => row.staffUserId === owner.id),
      "owner listed for manager"
    );

    const access = await jsonRequest(server, {
      method: "GET",
      path: "/seller-staff/access",
      token: ownerToken,
    });
    assert(access.status === 200, "list access");
    assert(
      access.json.staffAccess.some((row) => row.sellerUserId === seller.id),
      "kitchen appears in staffAccess"
    );

    const me = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me",
      token: ownerToken,
    });
    assert(me.status === 200, "GET /auth/me");
    assert(Array.isArray(me.json.staffAccess), "staffAccess additive on /me");
    assert(
      me.json.staffAccess.some((row) => row.sellerUserId === seller.id),
      "/me includes oversight kitchen"
    );

    const ownKitchen = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=active",
      token: sellerToken,
    });
    assert(ownKitchen.status === 200, "manager own kitchen unchanged");

    const ownerRead = await jsonRequest(server, {
      method: "GET",
      path: `/orders?role=seller&scope=active&kitchenSellerId=${encodeURIComponent(seller.id)}`,
      token: ownerToken,
    });
    assert(ownerRead.status === 200, `owner can read kitchen: ${ownerRead.status}`);
    assert(Array.isArray(ownerRead.json.orders), "owner gets orders envelope");

    const ownerStats = await jsonRequest(server, {
      method: "GET",
      path: `/orders/seller/stats?kitchenSellerId=${encodeURIComponent(seller.id)}`,
      token: ownerToken,
    });
    assert(ownerStats.status === 200, "owner can read stats");

    const ownerInsights = await jsonRequest(server, {
      method: "GET",
      path: `/orders/seller/insights?preset=last_7_days&kitchenSellerId=${encodeURIComponent(seller.id)}`,
      token: ownerToken,
    });
    assert(ownerInsights.status === 200, "owner can read insights");

    const strangerRead = await jsonRequest(server, {
      method: "GET",
      path: `/orders?role=seller&scope=active&kitchenSellerId=${encodeURIComponent(seller.id)}`,
      token: strangerToken,
    });
    assert(strangerRead.status === 403, "stranger cannot use kitchenSellerId");

    const listing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Staff test ${Date.now()}`,
        price: 55,
        quantity: 5,
        status: "active",
      },
    });

    let orderId = null;
    try {
      const created = await jsonRequest(server, {
        method: "POST",
        path: "/orders",
        token: buyerToken,
        body: {
          paymentMethod: "upi",
          items: [{ listingId: listing.id, quantity: 1 }],
        },
      });
      assert(
        created.status === 201,
        `order create: ${created.status} ${JSON.stringify(created.json)}`
      );
      orderId = created.json.id;

      const ownerOrder = await jsonRequest(server, {
        method: "GET",
        path: `/orders/${orderId}`,
        token: ownerToken,
      });
      assert(ownerOrder.status === 200, "owner can GET order by id");

      const ownerMsgs = await jsonRequest(server, {
        method: "GET",
        path: `/orders/${orderId}/messages`,
        token: ownerToken,
      });
      assert(ownerMsgs.status === 200, "owner can read messages");

      // Regular orders auto-accept; force pending so accept is still a write.
      await prisma.order.update({
        where: { id: orderId },
        data: { status: "pending", acceptedAt: null },
      });

      const ownerPatch = await jsonRequest(server, {
        method: "PATCH",
        path: `/orders/${orderId}/status`,
        token: ownerToken,
        body: { status: "accepted" },
      });
      assert(ownerPatch.status === 403, "owner cannot accept orders");

      const after = await prisma.order.findUnique({ where: { id: orderId } });
      assert(after.status === "pending", "order status unchanged after owner write attempt");
    } finally {
      if (orderId) {
        await prisma.message.deleteMany({ where: { orderId } });
        await prisma.orderItem.deleteMany({ where: { orderId } });
        await prisma.order.delete({ where: { id: orderId } }).catch(() => {});
      }
      await prisma.listing.delete({ where: { id: listing.id } }).catch(() => {});
    }

    console.log("seller-staff.test.js passed");
  } finally {
    await new Promise((resolve, reject) =>
      server.close((err) => (err ? reject(err) : resolve()))
    );
    await prisma.sellerStaffMembership.deleteMany({
      where: {
        OR: [
          { sellerUserId: seller.id, staffUserId: owner.id },
          { staffUserId: owner.id },
        ],
      },
    });
    await prisma.$disconnect().catch(() => {});
  }
}

main()
  .then(() => process.exit(0))
  .catch(async (err) => {
    console.error(err);
    await prisma.$disconnect().catch(() => {});
    process.exit(1);
  });
