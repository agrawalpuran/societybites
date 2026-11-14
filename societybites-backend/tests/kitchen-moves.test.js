require("dotenv").config();

const http = require("http");
const express = require("express");
const crypto = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const authRoutes = require("../routes/auth");
const adminRoutes = require("../routes/admin");
const { withFssaiSellingRequirement } = require("../lib/fssaiRequirement");

const SELLER_A = "+919800000481";
const SELLER_B = "+919800000484";
const ADMIN = "+919800000482";
const BUYER = "+919800000483";
const PROOF = "https://example.com/address-proofs/kitchen-move.jpg";
const PROOF_B = "https://example.com/address-proofs/kitchen-move-b.jpg";

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
        res.on("data", (chunk) => (data += chunk));
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
  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/admin", adminRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({ error: err.message });
  });
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  const created = {
    users: [],
    societies: [],
    flats: [],
    listings: [],
    campaigns: [],
    orders: [],
    moves: [],
  };

  try {
    const home = await prisma.society.findFirst({ where: { status: "active" } });
    assert(home, "seed society required");
    const stamp = Date.now().toString().slice(-6);
    const destination = await prisma.society.create({
      data: {
        name: `Move Society ${stamp}`,
        city: home.city || "Bengaluru",
        inviteCode: `MOVE${stamp}`,
        status: "active",
      },
    });
    created.societies.push(destination.id);

    const flat = await prisma.flat.create({
      data: {
        id: crypto.randomUUID(),
        flatNumber: `KM${stamp}`,
        block: "Kitchen",
        floor: 1,
        unit: "1",
        societyId: home.id,
      },
    });
    created.flats.push(flat.id);

    const sellerA = await prisma.user.upsert({
      where: { phone: SELLER_A },
      update: {
        name: "Kitchen Move Seller",
        role: "seller",
        societyId: home.id,
        flatId: flat.id,
        suspended: false,
        addressProofUrl: "https://example.com/address-proofs/old.jpg",
        addressProofStatus: "OK",
        fssaiNumber: "11111111111111",
      },
      create: {
        phone: SELLER_A,
        name: "Kitchen Move Seller",
        role: "seller",
        societyId: home.id,
        flatId: flat.id,
        addressProofUrl: "https://example.com/address-proofs/old.jpg",
        fssaiNumber: "11111111111111",
      },
    });
    created.users.push(sellerA.id);
    await prisma.sellerFssai.upsert({
      where: { userId: sellerA.id },
      update: {
        registrationNumber: "11111111111111",
        registeredName: "Old Kitchen",
        status: "APPROVED",
      },
      create: {
        userId: sellerA.id,
        registrationNumber: "11111111111111",
        registeredName: "Old Kitchen",
        status: "APPROVED",
      },
    });

    const sellerB = await prisma.user.upsert({
      where: { phone: SELLER_B },
      update: {
        name: "Flexible Move Seller",
        role: "seller",
        societyId: home.id,
        flatId: flat.id,
        suspended: false,
        addressProofUrl: "https://example.com/address-proofs/old-b.jpg",
        fssaiNumber: "22222222222222",
      },
      create: {
        phone: SELLER_B,
        name: "Flexible Move Seller",
        role: "seller",
        societyId: home.id,
        flatId: flat.id,
        addressProofUrl: "https://example.com/address-proofs/old-b.jpg",
        fssaiNumber: "22222222222222",
      },
    });
    created.users.push(sellerB.id);
    await prisma.sellerFssai.upsert({
      where: { userId: sellerB.id },
      update: { registrationNumber: "22222222222222", status: "APPROVED" },
      create: {
        userId: sellerB.id,
        registrationNumber: "22222222222222",
        registeredName: "Flexible Kitchen",
        status: "APPROVED",
      },
    });

    const admin = await prisma.user.upsert({
      where: { phone: ADMIN },
      update: { name: "Kitchen Move Admin", role: "super_admin", suspended: false },
      create: { phone: ADMIN, name: "Kitchen Move Admin", role: "super_admin" },
    });
    created.users.push(admin.id);
    const buyer = await prisma.user.upsert({
      where: { phone: BUYER },
      update: { name: "Kitchen Move Buyer", role: "buyer", societyId: home.id, suspended: false },
      create: {
        phone: BUYER,
        name: "Kitchen Move Buyer",
        role: "buyer",
        societyId: home.id,
      },
    });
    created.users.push(buyer.id);

    const listing = await prisma.listing.create({
      data: {
        sellerId: sellerA.id,
        societyId: home.id,
        name: `Move Dish ${stamp}`,
        price: 120,
        status: "active",
      },
    });
    created.listings.push(listing.id);
    const draft = await prisma.preOrderCampaign.create({
      data: {
        sellerId: sellerA.id,
        societyId: home.id,
        title: `Draft move ${stamp}`,
        status: "draft",
        orderOpenAt: new Date(),
        orderCutoffAt: new Date(Date.now() + 86400000),
        fulfilmentAt: new Date(Date.now() + 172800000),
      },
    });
    created.campaigns.push(draft.id);
    const closed = await prisma.preOrderCampaign.create({
      data: {
        sellerId: sellerA.id,
        societyId: home.id,
        title: `Closed move ${stamp}`,
        status: "closed",
        orderOpenAt: new Date(),
        orderCutoffAt: new Date(),
        fulfilmentAt: new Date(),
      },
    });
    created.campaigns.push(closed.id);
    const closedDish = await prisma.listing.create({
      data: {
        sellerId: sellerA.id,
        societyId: home.id,
        campaignId: closed.id,
        name: `Closed dish ${stamp}`,
        price: 80,
        status: "active",
      },
    });
    created.listings.push(closedDish.id);
    const order = await prisma.order.create({
      data: {
        orderNumber: `KM${stamp}`,
        buyerId: buyer.id,
        societyId: home.id,
        subtotal: 120,
        total: 120,
        status: "pending",
      },
    });
    created.orders.push(order.id);

    const sellerToken = signToken(sellerA);
    const sellerBToken = signToken(sellerB);
    const adminToken = signToken(admin);
    const buyerToken = signToken(buyer);

    const buyerTry = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/kitchen-move",
      token: buyerToken,
      body: { societyId: destination.id, addressProofUrl: PROOF },
    });
    assert(buyerTry.status === 403, "buyers cannot move a kitchen");

    const same = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/kitchen-move",
      token: sellerToken,
      body: { societyId: home.id, addressProofUrl: PROOF },
    });
    assert(same.status === 400, "same society is rejected");

    const submitted = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/kitchen-move",
      token: sellerToken,
      body: {
        societyId: destination.id,
        block: "B",
        flatNumber: `MV${stamp}`,
        addressProofUrl: PROOF,
      },
    });
    assert(submitted.status === 201, `submit move failed ${submitted.status}`);
    const moveId = submitted.json.move.id;
    created.moves.push(moveId);
    const afterSubmit = await prisma.user.findUnique({ where: { id: sellerA.id } });
    assert(afterSubmit.societyId === home.id, "submitting a move does not change the kitchen");
    assert(afterSubmit.addressProofUrl.includes("old.jpg"), "live proof stays until approval");

    const followUp = await jsonRequest(server, {
      method: "POST",
      path: `/admin/kitchen-moves/${moveId}/address-proof`,
      token: adminToken,
      body: { status: "FOLLOW_UP" },
    });
    assert(followUp.status === 200, "admin can mark the photo as follow-up");
    assert(followUp.json.move.addressProofStatus === "FOLLOW_UP", "proof status saved on the move");

    const earlyReview = await jsonRequest(server, {
      method: "POST",
      path: `/admin/kitchen-moves/${moveId}/fssai/needs-review`,
      token: adminToken,
    });
    assert(earlyReview.status === 400, "needs review requires an attached licence");

    await prisma.kitchenMove.update({
      where: { id: moveId },
      data: {
        fssaiRegistrationNumber: "33333333333333",
        fssaiRegisteredName: "New Kitchen",
        fssaiLicenceExpiry: new Date("2028-01-01T00:00:00.000Z"),
        fssaiDocumentStorageReference: "fssai-private/test/move.jpg",
        fssaiStatus: "NOT_SUBMITTED",
      },
    });
    const needsReview = await jsonRequest(server, {
      method: "POST",
      path: `/admin/kitchen-moves/${moveId}/fssai/needs-review`,
      token: adminToken,
    });
    assert(needsReview.status === 200, "needs review works when the photo is not proper");
    assert(needsReview.json.move.fssaiStatus === "UNDER_REVIEW", "FSSAI is in review");
    const stillHome = await prisma.user.findUnique({ where: { id: sellerA.id } });
    assert(stillHome.societyId === home.id, "FSSAI review does not move the kitchen");
    const liveLicence = await prisma.sellerFssai.findUnique({ where: { userId: sellerA.id } });
    assert(liveLicence.registrationNumber === "11111111111111", "live licence stays until the move is approved");

    const approvedLicence = await jsonRequest(server, {
      method: "POST",
      path: `/admin/kitchen-moves/${moveId}/fssai/approve`,
      token: adminToken,
    });
    assert(approvedLicence.status === 200, "admin can approve the move licence");
    const afterLicence = await prisma.user.findUnique({ where: { id: sellerA.id } });
    assert(afterLicence.societyId === home.id, "approving the licence does not change the address");

    await withFssaiSellingRequirement(true, async () => {
      const blocked = await jsonRequest(server, {
        method: "POST",
        path: `/admin/kitchen-moves/${moveId}/approve`,
        token: adminToken,
      });
      assert(blocked.status === 200, "an approved new-area licence lets the move through when FSSAI is required");
    });
    const moved = await prisma.user.findUnique({ where: { id: sellerA.id } });
    assert(moved.societyId === destination.id, "address changes only after the move is approved");
    assert(moved.addressProofUrl === PROOF, "new proof replaces the live photo on approval");
    const movedLicence = await prisma.sellerFssai.findUnique({ where: { userId: sellerA.id } });
    assert(movedLicence.registrationNumber === "33333333333333", "approved move licence becomes the live licence");
    assert(movedLicence.status === "APPROVED", "live licence is approved");
    const movedListing = await prisma.listing.findUnique({ where: { id: listing.id } });
    assert(movedListing.societyId === destination.id, "open dishes follow the kitchen");
    const movedDraft = await prisma.preOrderCampaign.findUnique({ where: { id: draft.id } });
    assert(movedDraft.societyId === destination.id, "open campaigns follow the kitchen");
    const stayedClosed = await prisma.preOrderCampaign.findUnique({ where: { id: closed.id } });
    assert(stayedClosed.societyId === home.id, "closed campaigns stay with the old society");
    const stayedDish = await prisma.listing.findUnique({ where: { id: closedDish.id } });
    assert(stayedDish.societyId === home.id, "closed campaign dishes stay put");
    const stayedOrder = await prisma.order.findUnique({ where: { id: order.id } });
    assert(stayedOrder.societyId === home.id, "existing orders keep the society from checkout");

    const flexible = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/kitchen-move",
      token: sellerBToken,
      body: { societyId: destination.id, addressProofUrl: PROOF_B },
    });
    assert(flexible.status === 201, "seller can request a move without a new licence");
    created.moves.push(flexible.json.move.id);
    await withFssaiSellingRequirement(true, async () => {
      const blocked = await jsonRequest(server, {
        method: "POST",
        path: `/admin/kitchen-moves/${flexible.json.move.id}/approve`,
        token: adminToken,
      });
      assert(blocked.status === 400, "FSSAI on blocks a move that has no approved licence");
    });
    const blockedUser = await prisma.user.findUnique({ where: { id: sellerB.id } });
    assert(blockedUser.societyId === home.id, "a blocked approval leaves the kitchen");

    const rejected = await jsonRequest(server, {
      method: "POST",
      path: `/admin/kitchen-moves/${flexible.json.move.id}/reject`,
      token: adminToken,
      body: { rejectionReason: "Need a clearer photo" },
    });
    assert(rejected.status === 200, "admin can reject a move");
    const afterReject = await prisma.user.findUnique({ where: { id: sellerB.id } });
    assert(afterReject.societyId === home.id, "rejection leaves the kitchen");

    const again = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/kitchen-move",
      token: sellerBToken,
      body: { societyId: destination.id, addressProofUrl: PROOF_B },
    });
    assert(again.status === 201, "seller can request again after a rejection");
    created.moves.push(again.json.move.id);
    await withFssaiSellingRequirement(false, async () => {
      const allowed = await jsonRequest(server, {
        method: "POST",
        path: `/admin/kitchen-moves/${again.json.move.id}/approve`,
        token: adminToken,
      });
      assert(allowed.status === 200, "FSSAI off lets admin approve without a new licence");
    });
    const flexibleUser = await prisma.user.findUnique({ where: { id: sellerB.id } });
    assert(flexibleUser.societyId === destination.id, "flexible approval moves the kitchen");
    const flexibleLicence = await prisma.sellerFssai.findUnique({ where: { userId: sellerB.id } });
    assert(
      flexibleLicence.registrationNumber === "22222222222222",
      "a move without a new licence leaves the current FSSAI"
    );

    console.log("kitchen move tests passed");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (created.orders.length) {
      await prisma.order.deleteMany({ where: { id: { in: created.orders } } });
    }
    if (created.listings.length) {
      await prisma.listing.deleteMany({ where: { id: { in: created.listings } } });
    }
    if (created.campaigns.length) {
      await prisma.preOrderCampaign.deleteMany({ where: { id: { in: created.campaigns } } });
    }
    if (created.users.length) {
      const moves = await prisma.kitchenMove.findMany({
        where: { userId: { in: created.users } },
        select: { toFlatId: true },
      });
      const extraFlats = moves.map((row) => row.toFlatId).filter(Boolean);
      await prisma.auditLog.deleteMany({ where: { adminId: { in: created.users } } });
      await prisma.kitchenMove.deleteMany({ where: { userId: { in: created.users } } });
      await prisma.sellerFssai.deleteMany({ where: { userId: { in: created.users } } });
      await prisma.user.deleteMany({ where: { id: { in: created.users } } });
      await prisma.flat.deleteMany({
        where: { id: { in: [...created.flats, ...extraFlats] } },
      });
    } else if (created.flats.length) {
      await prisma.flat.deleteMany({ where: { id: { in: created.flats } } });
    }
    if (created.societies.length) {
      await prisma.society.deleteMany({ where: { id: { in: created.societies } } });
    }
    await prisma.$disconnect();
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
