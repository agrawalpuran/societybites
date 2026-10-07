require("dotenv").config();

const http = require("http");
const express = require("express");
const crypto = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const authRoutes = require("../routes/auth");
const adminRoutes = require("../routes/admin");
const fssaiRoutes = require("../routes/fssai");
const orderRoutes = require("../routes/orders");
const listingRoutes = require("../routes/listings");
const {
  isFssaiSellingRequirementEnabled,
  setFssaiSellingRequirement,
} = require("../lib/fssaiRequirement");

const SELLER_PHONE = "+919800000301";
const SELLER2_PHONE = "+919800000302";
const BUYER_PHONE = "+919800000303";
const ADMIN_PHONE = "+919800000304";

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
  const requirementBeforeTests = await isFssaiSellingRequirementEnabled();

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/admin", adminRoutes);
  app.use("/fssai", fssaiRoutes);
  app.use("/orders", orderRoutes);
  app.use("/listings", listingRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({ error: err.message, code: err.code });
  });
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  const created = { users: [], listings: [], orders: [] };

  try {
    await setFssaiSellingRequirement(false);
    const society = await prisma.society.findFirst();
    assert(society, "seed society required");

    const seller = await prisma.user.upsert({
      where: { phone: SELLER_PHONE },
      update: { role: "seller", societyId: society.id, suspended: false },
      create: {
        phone: SELLER_PHONE,
        name: "FSSAI Seller",
        role: "seller",
        societyId: society.id,
        upiId: "seller@oksbi",
        paymentEnabled: true,
      },
    });
    const seller2 = await prisma.user.upsert({
      where: { phone: SELLER2_PHONE },
      update: { role: "seller", societyId: society.id },
      create: {
        phone: SELLER2_PHONE,
        name: "Other Seller",
        role: "seller",
        societyId: society.id,
      },
    });
    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { role: "buyer", societyId: society.id },
      create: {
        phone: BUYER_PHONE,
        name: "FSSAI Buyer",
        role: "buyer",
        societyId: society.id,
      },
    });
    const admin = await prisma.user.upsert({
      where: { phone: ADMIN_PHONE },
      update: { role: "super_admin", societyId: society.id },
      create: {
        phone: ADMIN_PHONE,
        name: "FSSAI Admin",
        role: "super_admin",
        societyId: society.id,
      },
    });
    created.users.push(seller.id, seller2.id, buyer.id, admin.id);

    await prisma.sellerFssai.deleteMany({ where: { userId: { in: created.users } } });
    await prisma.fssaiAssistanceRequest.deleteMany({ where: { userId: { in: created.users } } });

    const sellerToken = signToken(seller);
    const seller2Token = signToken(seller2);
    const buyerToken = signToken(buyer);
    const adminToken = signToken(admin);

    const settings = await jsonRequest(server, { method: "GET", path: "/admin/settings", token: adminToken });
    assert(settings.status === 200, "admin settings");
    assert(settings.json.fssaiSellingRequirement === false, "requirement defaults off");

    const me0 = await jsonRequest(server, { method: "GET", path: "/fssai/me", token: sellerToken });
    assert(me0.status === 200, "seller fssai me");
    assert(me0.json.fssai.status === "NOT_SUBMITTED", "initial status");

    const docPath = `fssai-private/${seller.id.slice(0, 8)}/test-doc.jpg`;
    await prisma.sellerFssai.create({
      data: {
        id: crypto.randomUUID(),
        userId: seller.id,
        documentStorageReference: docPath,
        documentType: "image/jpeg",
        status: "NOT_SUBMITTED",
      },
    });

    const submitted = await jsonRequest(server, {
      method: "POST",
      path: "/fssai/me/submit",
      token: sellerToken,
      body: {
        registrationNumber: "12345678901234",
        registeredName: "Test Kitchen",
        licenceExpiry: "2030-12-31",
        storageReference: docPath,
      },
    });
    assert(submitted.status === 200, `submit ${submitted.status} ${JSON.stringify(submitted.json)}`);
    assert(submitted.json.fssai.status === "UNDER_REVIEW", "under review");

    const pending = await jsonRequest(server, {
      method: "GET",
      path: "/admin/fssai/submissions?status=UNDER_REVIEW",
      token: adminToken,
    });
    assert(pending.status === 200, "admin list");
    assert(
      pending.json.records.some((row) => row.sellerId === seller.id),
      "admin sees pending"
    );

    const buyerBlocked = await jsonRequest(server, {
      method: "GET",
      path: "/admin/fssai/submissions",
      token: buyerToken,
    });
    assert(buyerBlocked.status === 403, "buyer cannot admin");

    const buyerFssai = await jsonRequest(server, {
      method: "GET",
      path: "/fssai/me",
      token: buyerToken,
    });
    assert(buyerFssai.status === 200, "buyer in society can view own FSSAI during onboarding");
    assert(buyerFssai.json.fssai.status === "NOT_SUBMITTED", "buyer fssai initial");

    const draft = await jsonRequest(server, {
      method: "POST",
      path: "/fssai/me/draft",
      token: seller2Token,
      body: {
        registrationNumber: "98765432109876",
        registeredName: "Partial Kitchen",
      },
    });
    assert(draft.status === 200, `draft save ${JSON.stringify(draft.json)}`);
    assert(draft.json.fssai.registrationNumber === "98765432109876", "draft number saved");
    assert(draft.json.fssai.detailsDeferred === false, "draft clears defer");

    const defer = await jsonRequest(server, {
      method: "POST",
      path: "/fssai/me/defer",
      token: buyerToken,
    });
    assert(defer.status === 200, `defer ${JSON.stringify(defer.json)}`);
    assert(defer.json.fssai.detailsDeferred === true, "deferred flag set");

    const reject = await jsonRequest(server, {
      method: "POST",
      path: `/admin/fssai/submissions/${seller.id}/reject`,
      token: adminToken,
      body: { rejectionReason: "Document unclear" },
    });
    assert(reject.status === 200, "reject");
    assert(reject.json.fssai.status === "REJECTED", "rejected");

    const meRejected = await jsonRequest(server, { method: "GET", path: "/fssai/me", token: sellerToken });
    assert(meRejected.json.fssai.rejectionReason === "Document unclear", "seller sees reason");

    const resubmit = await jsonRequest(server, {
      method: "POST",
      path: "/fssai/me/submit",
      token: sellerToken,
      body: {
        registrationNumber: "12345678901234",
        registeredName: "Test Kitchen",
        licenceExpiry: "2030-12-31",
      },
    });
    assert(resubmit.status === 200, "resubmit");
    assert(resubmit.json.fssai.status === "UNDER_REVIEW", "back under review");
    assert(!resubmit.json.fssai.rejectionReason, "cleared rejection");

    const approve = await jsonRequest(server, {
      method: "POST",
      path: `/admin/fssai/submissions/${seller.id}/approve`,
      token: adminToken,
    });
    assert(approve.status === 200, "approve");
    assert(approve.json.fssai.status === "APPROVED", "approved");

    const assistance = await jsonRequest(server, {
      method: "POST",
      path: "/fssai/me/assistance",
      token: sellerToken,
    });
    assert(assistance.status === 201, "assistance");
    const adminAssist = await jsonRequest(server, {
      method: "GET",
      path: "/admin/fssai/assistance",
      token: adminToken,
    });
    assert(adminAssist.json.requests.length >= 1, "admin sees assistance");

    const listing = await prisma.listing.create({
      data: {
        id: crypto.randomUUID(),
        name: "FSSAI Test Dish",
        description: "Test",
        price: 50,
        quantity: 5,
        status: "active",
        societyId: society.id,
        sellerId: seller.id,
        catalogType: "REGULAR",
        foodType: "VEG",
        category: "Snacks",
        categories: ["Snacks"],
      },
    });
    created.listings.push(listing.id);

    await setFssaiSellingRequirement(true);

    const draftBlocked = await jsonRequest(server, {
      method: "POST",
      path: "/fssai/me/draft",
      token: seller2Token,
      body: { registrationNumber: "11111111111111" },
    });
    assert(draftBlocked.status === 400, "draft blocked when requirement on");

    const deferBlocked = await jsonRequest(server, {
      method: "POST",
      path: "/fssai/me/defer",
      token: buyerToken,
    });
    assert(deferBlocked.status === 400, "defer blocked when requirement on");

    await prisma.sellerFssai.upsert({
      where: { userId: seller2.id },
      update: { status: "NOT_SUBMITTED", rejectionReason: null },
      create: {
        id: crypto.randomUUID(),
        userId: seller2.id,
        status: "NOT_SUBMITTED",
      },
    });

    const listing2 = await prisma.listing.create({
      data: {
        id: crypto.randomUUID(),
        name: "Blocked Dish",
        description: "Test",
        price: 40,
        quantity: 3,
        status: "active",
        societyId: society.id,
        sellerId: seller2.id,
        catalogType: "REGULAR",
        foodType: "VEG",
        category: "Snacks",
        categories: ["Snacks"],
      },
    });
    created.listings.push(listing2.id);

    const orderBlocked = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        items: [{ listingId: listing2.id, quantity: 1 }],
        paymentMethod: "cash",
      },
    });
    assert(orderBlocked.status === 400, "order blocked when requirement on");
    assert(orderBlocked.json.code === "FSSAI_REQUIRED", "fssai code");

    const countAfter = await prisma.listing.count({ where: { sellerId: seller2.id } });
    assert(countAfter >= 1, "listings not deleted");

    console.log("fssai compliance ok");
  } finally {
    server.close();
    if (created.orders.length) {
      await prisma.orderItem.deleteMany({ where: { orderId: { in: created.orders } } });
      await prisma.order.deleteMany({ where: { id: { in: created.orders } } });
    }
    if (created.listings.length) {
      await prisma.listing.deleteMany({ where: { id: { in: created.listings } } });
    }
    if (created.users.length) {
      await prisma.fssaiAssistanceRequest.deleteMany({ where: { userId: { in: created.users } } });
      await prisma.sellerFssai.deleteMany({ where: { userId: { in: created.users } } });
      await prisma.user.deleteMany({ where: { id: { in: created.users } } });
    }
    await setFssaiSellingRequirement(requirementBeforeTests);
    await prisma.$disconnect();
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
