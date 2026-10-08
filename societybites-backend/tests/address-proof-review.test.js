require("dotenv").config();

const http = require("http");
const express = require("express");
const crypto = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const adminRoutes = require("../routes/admin");
const { acceptSellerTermsAndEnable } = require("../lib/sellerTerms");

const SELLER_PHONE = "+919800000411";
const ADMIN_PHONE = "+919800000412";
const BUYER_PHONE = "+919800000413";
const PROOF = "https://example.com/address-proofs/review-proof.jpg";
const REPLACEMENT = "https://example.com/address-proofs/review-proof-2.jpg";

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
  const app = express();
  app.use(express.json());
  app.use("/admin", adminRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({ error: err.message });
  });
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  const created = { users: [], flats: [] };

  try {
    const society = await prisma.society.findFirst();
    assert(society, "seed society required");

    const flat = await prisma.flat.create({
      data: {
        id: crypto.randomUUID(),
        flatNumber: `AP${Date.now().toString().slice(-6)}`,
        block: "Proof Block",
        floor: 1,
        unit: "1",
        societyId: society.id,
      },
    });
    created.flats.push(flat.id);

    const seller = await prisma.user.upsert({
      where: { phone: SELLER_PHONE },
      update: {
        name: "Address Proof Seller",
        role: "seller",
        societyId: society.id,
        flatId: flat.id,
        suspended: false,
        addressProofUrl: PROOF,
        addressProofStatus: null,
        addressProofReviewedAt: null,
        addressProofReviewedBy: null,
      },
      create: {
        phone: SELLER_PHONE,
        name: "Address Proof Seller",
        role: "seller",
        societyId: society.id,
        flatId: flat.id,
        addressProofUrl: PROOF,
      },
    });
    created.users.push(seller.id);
    const admin = await prisma.user.upsert({
      where: { phone: ADMIN_PHONE },
      update: { name: "Address Proof Admin", role: "super_admin", suspended: false },
      create: {
        phone: ADMIN_PHONE,
        name: "Address Proof Admin",
        role: "super_admin",
      },
    });
    created.users.push(admin.id);
    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { name: "Address Proof Buyer", role: "buyer", suspended: false },
      create: {
        phone: BUYER_PHONE,
        name: "Address Proof Buyer",
        role: "buyer",
      },
    });
    created.users.push(buyer.id);

    const adminToken = signToken(admin);
    const buyerToken = signToken(buyer);

    const denied = await jsonRequest(server, {
      method: "GET",
      path: "/admin/address-proofs",
      token: buyerToken,
    });
    assert(denied.status === 403, "buyers cannot list address proofs");

    const pending = await jsonRequest(server, {
      method: "GET",
      path: "/admin/address-proofs?status=PENDING",
      token: adminToken,
    });
    assert(pending.status === 200, "admin can list pending proofs");
    const row = pending.json.records.find((item) => item.userId === seller.id);
    assert(row, "unreviewed photo is pending");
    assert(row.addressProofUrl === undefined, "list hides the photo URL");
    assert(row.societyName === society.name, "list includes society");
    assert(row.flatNumber === flat.flatNumber, "list includes flat");
    assert(row.block === "Proof Block", "list includes block");

    const detail = await jsonRequest(server, {
      method: "GET",
      path: `/admin/address-proofs/${seller.id}`,
      token: adminToken,
    });
    assert(detail.status === 200, "admin can open the photo");
    assert(detail.json.record.addressProofUrl === PROOF, "detail includes the photo URL");

    const marked = await jsonRequest(server, {
      method: "POST",
      path: `/admin/address-proofs/${seller.id}/review`,
      token: adminToken,
      body: { status: "OK" },
    });
    assert(marked.status === 200, "admin can mark the photo");
    assert(marked.json.record.status === "OK", "status is looks fine");

    const after = await prisma.user.findUnique({ where: { id: seller.id } });
    assert(after.role === "seller", "review does not change role");
    assert(after.suspended === false, "review does not suspend the seller");
    assert(after.addressProofReviewedBy === admin.id, "review records the admin");

    const stillPending = await jsonRequest(server, {
      method: "GET",
      path: "/admin/address-proofs?status=PENDING",
      token: adminToken,
    });
    assert(
      !stillPending.json.records.some((item) => item.userId === seller.id),
      "reviewed photo leaves the pending list"
    );

    const audit = await prisma.auditLog.findFirst({
      where: { adminId: admin.id, action: "ADDRESS_PROOF_REVIEW", target: seller.id },
    });
    assert(audit, "review is written to the audit log");

    const bad = await jsonRequest(server, {
      method: "POST",
      path: `/admin/address-proofs/${seller.id}/review`,
      token: adminToken,
      body: { status: "APPROVED" },
    });
    assert(bad.status === 400, "unknown status is rejected");

    const replaced = await acceptSellerTermsAndEnable({
      prisma,
      user: after,
      body: { termsVersion: "1.0", addressProofUrl: REPLACEMENT },
    });
    assert(replaced.user.addressProofStatus === "PENDING", "a new photo returns to pending");
    assert(replaced.user.addressProofReviewedAt === null, "a new photo clears the review time");

    const same = await acceptSellerTermsAndEnable({
      prisma,
      user: replaced.user,
      body: { termsVersion: "1.0", addressProofUrl: REPLACEMENT },
    });
    await reviewAddressProofDirect(admin, seller.id);
    const kept = await acceptSellerTermsAndEnable({
      prisma,
      user: { ...same.user, addressProofStatus: "OK", addressProofUrl: REPLACEMENT },
      body: { termsVersion: "1.0", addressProofUrl: REPLACEMENT },
    });
    assert(kept.user.addressProofStatus === "OK", "the same photo keeps its review");

    console.log("address proof review ok");
  } finally {
    server.close();
    if (created.users.length) {
      await prisma.auditLog.deleteMany({ where: { adminId: { in: created.users } } });
      await prisma.sellerTermsAcceptance.deleteMany({ where: { userId: { in: created.users } } });
      await prisma.user.deleteMany({ where: { id: { in: created.users } } });
    }
    if (created.flats.length) {
      await prisma.flat.deleteMany({ where: { id: { in: created.flats } } });
    }
    await prisma.$disconnect();
  }
}

async function reviewAddressProofDirect(admin, userId) {
  await prisma.user.update({
    where: { id: userId },
    data: {
      addressProofStatus: "OK",
      addressProofReviewedAt: new Date(),
      addressProofReviewedBy: admin.id,
    },
  });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
