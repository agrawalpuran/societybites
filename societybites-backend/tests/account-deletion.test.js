require("dotenv").config();

const http = require("http");
const express = require("express");
const crypto = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { deleteAuthenticatedAccount } = require("../lib/accountDeletion");
const authRoutes = require("../routes/auth");

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

async function cleanupUser(userId) {
  if (!userId) return;
  await prisma.review.deleteMany({ where: { reviewerId: userId } });
  await prisma.orderItem.deleteMany({
    where: { order: { buyerId: userId } },
  });
  await prisma.order.deleteMany({ where: { buyerId: userId } });
  await prisma.listing.deleteMany({ where: { sellerId: userId } });
  await prisma.preOrderCampaign.deleteMany({ where: { sellerId: userId } });
  await prisma.refreshToken.deleteMany({ where: { userId } });
  await prisma.deviceToken.deleteMany({ where: { userId } });
  await prisma.user.deleteMany({ where: { id: userId } });
}

async function main() {
  const stamp = String(Date.now()).slice(-8);
  const society = await prisma.society.findFirst({
    where: { status: "active" },
  });
  assert(society, "seed society required");

  const victimPhone = `+9197${stamp}01`;
  const otherPhone = `+9197${stamp}02`;
  const sellerPhone = `+9197${stamp}03`;

  let victimId;
  let otherId;
  let sellerId;
  let listingId;
  let orderId;
  let campaignId;
  let reviewId;

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  try {
    const victim = await prisma.user.create({
      data: {
        phone: victimPhone,
        name: "Delete Me",
        role: "seller",
        upiId: "deleteme@upi",
        upiDisplayName: "Delete Me",
        paymentEnabled: true,
        societyId: society.id,
        sellingReachLevel: "NEARBY",
        fulfilmentMode: "SELLER_DELIVERY",
        deliveryCharge: 40,
      },
    });
    victimId = victim.id;

    const other = await prisma.user.create({
      data: {
        phone: otherPhone,
        name: "Other User",
        role: "buyer",
        societyId: society.id,
      },
    });
    otherId = other.id;

    const seller = await prisma.user.create({
      data: {
        phone: sellerPhone,
        name: "Seller Keep",
        role: "seller",
        societyId: society.id,
      },
    });
    sellerId = seller.id;

    const listing = await prisma.listing.create({
      data: {
        sellerId: victimId,
        societyId: society.id,
        name: "Victim Listing",
        price: 100,
        quantity: 5,
        status: "active",
        catalogType: "REGULAR",
      },
    });
    listingId = listing.id;

    const campaign = await prisma.preOrderCampaign.create({
      data: {
        sellerId: victimId,
        societyId: society.id,
        title: "Open Campaign",
        orderOpenAt: new Date(Date.now() - 3600_000),
        orderCutoffAt: new Date(Date.now() + 86400_000),
        fulfilmentAt: new Date(Date.now() + 172800_000),
        status: "open",
      },
    });
    campaignId = campaign.id;

    const order = await prisma.order.create({
      data: {
        orderNumber: `DEL-${stamp}`,
        buyerId: victimId,
        societyId: society.id,
        status: "completed",
        subtotal: 100,
        total: 100,
        paymentStatus: "paid",
        items: {
          create: [
            {
              listingId,
              quantity: 1,
              unitPrice: 100,
            },
          ],
        },
      },
    });
    orderId = order.id;

    const review = await prisma.review.create({
      data: {
        orderId,
        listingId,
        reviewerId: victimId,
        rating: 5,
        comment: "Personal review text",
        tags: ["tasty"],
      },
    });
    reviewId = review.id;

    await prisma.refreshToken.create({
      data: {
        userId: victimId,
        tokenHash: crypto.createHash("sha256").update(`rt-${stamp}`).digest("hex"),
        expiresAt: new Date(Date.now() + 86400_000),
      },
    });
    await prisma.deviceToken.create({
      data: {
        userId: victimId,
        token: `fcm-delete-${stamp}`,
        platform: "android",
      },
    });

    // Unauthenticated delete must fail.
    const unauth = await jsonRequest(server, {
      method: "DELETE",
      path: "/auth/me",
    });
    assert(unauth.status === 401, "unauthenticated delete must be 401");

    // No client-supplied userId route — /auth/users/:id must not exist.
    const otherToken = signToken(other);
    const missingRoute = await jsonRequest(server, {
      method: "DELETE",
      path: `/auth/users/${otherId}`,
      token: otherToken,
    });
    assert(
      missingRoute.status === 404 || missingRoute.status === 405,
      "must not expose DELETE by arbitrary user id"
    );
    const otherStill = await prisma.user.findUnique({ where: { id: otherId } });
    assert(otherStill.phone === otherPhone, "other untouched by missing route");

    // Victim deletes own account; body.userId must be ignored (token scopes identity).
    const victimToken = signToken(victim);
    const del = await jsonRequest(server, {
      method: "DELETE",
      path: "/auth/me",
      token: victimToken,
      body: { userId: sellerId },
    });
    assert(del.status === 200, `delete status ${del.status}`);
    assert(del.json && del.json.success === true, "success true");

    const after = await prisma.user.findUnique({ where: { id: victimId } });
    assert(after.suspended === true, "victim suspended");
    assert(after.phone === `deleted_${victimId}`, "phone anonymized");
    assert(after.name === null, "name cleared");
    assert(after.upiId === null, "upi cleared");
    assert(after.upiDisplayName === null, "upi display cleared");
    assert(after.paymentEnabled === false, "payment disabled");
    assert(after.societyId === null, "society cleared");
    assert(after.flatId === null, "flat cleared");
    assert(after.role === "buyer", "role reset");

    const sellerAfter = await prisma.user.findUnique({ where: { id: sellerId } });
    assert(sellerAfter.phone === sellerPhone, "client-supplied userId ignored");
    assert(sellerAfter.suspended === false, "other seller not suspended");
    assert(otherStill.phone === otherPhone, "non-target other still intact");

    const listingAfter = await prisma.listing.findUnique({ where: { id: listingId } });
    assert(listingAfter.status === "inactive", "listings deactivated");
    assert(listingAfter.sellerId === victimId, "listing seller FK retained");

    const campaignAfter = await prisma.preOrderCampaign.findUnique({
      where: { id: campaignId },
    });
    assert(campaignAfter.status === "cancelled", "open campaign cancelled");
    assert(campaignAfter.sellerId === victimId, "campaign seller FK retained");

    const orderAfter = await prisma.order.findUnique({ where: { id: orderId } });
    assert(orderAfter, "order retained for marketplace history");
    assert(orderAfter.buyerId === victimId, "order buyer FK retained");

    const reviewAfter = await prisma.review.findUnique({ where: { id: reviewId } });
    assert(reviewAfter.hidden === true, "review hidden");
    assert(reviewAfter.comment === null, "review comment cleared");

    const tokens = await prisma.refreshToken.count({ where: { userId: victimId } });
    const devices = await prisma.deviceToken.count({ where: { userId: victimId } });
    assert(tokens === 0, "refresh tokens revoked");
    assert(devices === 0, "device tokens removed");

    // Leftover JWT must not authorize further actions.
    const blocked = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me",
      token: victimToken,
    });
    assert(blocked.status === 403, "suspended account blocked");

    // Helper must not wipe an unrelated user when called with victim id only.
    const helper = await deleteAuthenticatedAccount(victimId);
    assert(helper.alreadyDeleted === true, "idempotent deletion");

    // Failure leaves account intact: invalid token does not mutate seller.
    const bad = await jsonRequest(server, {
      method: "DELETE",
      path: "/auth/me",
      token: "not-a-jwt",
    });
    assert(bad.status === 401, "bad token rejected");
    const sellerStill = await prisma.user.findUnique({ where: { id: sellerId } });
    assert(sellerStill.phone === sellerPhone, "failure leaves other accounts intact");

    console.log("account-deletion.test.js: PASS");
  } finally {
    server.close();
    await cleanupUser(victimId);
    await cleanupUser(otherId);
    await cleanupUser(sellerId);
    await prisma.$disconnect();
  }
}

main().catch(async (err) => {
  console.error("account-deletion.test.js: FAIL");
  console.error(err);
  try {
    await prisma.$disconnect();
  } catch (_) {}
  process.exit(1);
});
