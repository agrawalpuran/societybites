require("dotenv").config();
const http = require("http");
const express = require("express");
const crypto = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { SELLER_TERMS_VERSION } = require("../lib/sellerTerms");
const {
  isFssaiSellingRequirementEnabled,
  setFssaiSellingRequirement,
} = require("../lib/fssaiRequirement");
const authRoutes = require("../routes/auth");

const BUYER_PHONE = "+919800000201";
const SELLER_PHONE = "+919800000202";

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
  assert(SELLER_TERMS_VERSION === "1.0", "canonical seller terms version is 1.0");

  const requirementBeforeTests = await isFssaiSellingRequirementEnabled();
  const created = [];
  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use((err, req, res, next) => {
    const statusCode = err.statusCode || 500;
    const payload = { error: err.message };
    if (typeof err.code === "string" && err.code.length > 0) {
      payload.code = err.code;
    }
    res.status(statusCode).json(payload);
  });
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    await setFssaiSellingRequirement(false);
    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { role: "buyer", paymentPreference: "UPI_AND_COD", suspended: false },
      create: { phone: BUYER_PHONE, name: "Terms Buyer", role: "buyer" },
    });
    const seller = await prisma.user.upsert({
      where: { phone: SELLER_PHONE },
      update: { role: "seller", paymentPreference: "UPI_AND_COD", suspended: false },
      create: { phone: SELLER_PHONE, name: "Existing Seller", role: "seller" },
    });
    created.push(buyer.id, seller.id);
    await prisma.sellerTermsAcceptance.deleteMany({
      where: { userId: { in: created } },
    });
    await prisma.sellerFssai.deleteMany({ where: { userId: { in: created } } });

    const buyerToken = signToken(buyer);
    const sellerToken = signToken(seller);

    const blocked = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: buyerToken,
      body: { role: "seller" },
    });
    assert(blocked.status === 400, `buyer PATCH role seller should fail: ${blocked.status}`);
    const stillBuyer = await prisma.user.findUnique({ where: { id: buyer.id } });
    assert(stillBuyer.role === "buyer", "seller is not enabled before acceptance");
    const none = await prisma.sellerTermsAcceptance.count({ where: { userId: buyer.id } });
    assert(none === 0, "declined or missing acceptance writes no row");

    const clientTime = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/seller-terms",
      token: buyerToken,
      body: { termsVersion: "1.0", acceptedAt: "2000-01-01T00:00:00.000Z" },
    });
    assert(clientTime.status === 400, "client acceptedAt is rejected");
    const afterClientTime = await prisma.user.findUnique({ where: { id: buyer.id } });
    assert(afterClientTime.role === "buyer", "rejected acceptedAt does not enable selling");

    const wrongVersion = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/seller-terms",
      token: buyerToken,
      body: { termsVersion: "9.9" },
    });
    assert(wrongVersion.status === 400, "unknown terms version is rejected");

    const existingSave = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { paymentPreference: "UPI_ONLY" },
    });
    assert(existingSave.status === 200, `existing seller save failed: ${existingSave.status} ${JSON.stringify(existingSave.json)}`);
    assert(existingSave.json.user.role === "seller", "existing seller stays a seller");
    assert(existingSave.json.user.paymentPreference === "UPI_ONLY", "existing seller settings still save");
    const sellerRows = await prisma.sellerTermsAcceptance.count({ where: { userId: seller.id } });
    assert(sellerRows === 0, "existing sellers are not required to accept terms");

    const noProof = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/seller-terms",
      token: buyerToken,
      body: { termsVersion: "1.0", paymentPreference: "UPI_ONLY" },
    });
    assert(noProof.status === 400, "address proof is required for new sellers");
    assert(
      String(noProof.json.error).includes("Address proof"),
      "missing proof message"
    );

    const proofUrl = "https://example.com/address-proofs/buyer-proof.jpg";

    await setFssaiSellingRequirement(true);
    const fssaiBlocked = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/seller-terms",
      token: buyerToken,
      body: {
        termsVersion: "1.0",
        paymentPreference: "UPI_ONLY",
        addressProofUrl: proofUrl,
      },
    });
    assert(fssaiBlocked.status === 400, `FSSAI gate: ${fssaiBlocked.status}`);
    assert(fssaiBlocked.json.code === "FSSAI_SUBMIT_REQUIRED", "fssai submit code");
    const stillBuyerAfterFssai = await prisma.user.findUnique({ where: { id: buyer.id } });
    assert(stillBuyerAfterFssai.role === "buyer", "FSSAI gate keeps buyer role");

    await prisma.sellerFssai.create({
      data: {
        id: crypto.randomUUID(),
        userId: buyer.id,
        status: "UNDER_REVIEW",
        submittedAt: new Date(),
      },
    });

    const before = Date.now();
    const accepted = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/seller-terms",
      token: buyerToken,
      body: {
        termsVersion: "1.0",
        paymentPreference: "UPI_ONLY",
        addressProofUrl: proofUrl,
      },
    });
    const after = Date.now();
    assert(accepted.status === 200, `accept failed: ${accepted.status} ${JSON.stringify(accepted.json)}`);
    assert(accepted.json.user.role === "seller", "acceptance enables selling");
    assert(accepted.json.user.paymentPreference === "UPI_ONLY", "pending settings save with acceptance");
    assert(accepted.json.user.addressProofUrl === proofUrl, "address proof URL is stored");
    assert(accepted.json.user.addressProofStatus === "PENDING", "new proof waits for admin review");
    assert(accepted.json.sellerTerms.termsVersion === "1.0", "response records termsVersion 1.0");
    const acceptedAt = new Date(accepted.json.sellerTerms.acceptedAt).getTime();
    assert(
      acceptedAt >= before - 2000 && acceptedAt <= after + 2000,
      "acceptedAt is generated on the server"
    );

    const row = await prisma.sellerTermsAcceptance.findUnique({
      where: { userId_termsVersion: { userId: buyer.id, termsVersion: "1.0" } },
    });
    assert(row, "acceptance row stored");
    assert(row.termsVersion === "1.0", "stored termsVersion is 1.0");
    assert(
      Math.abs(row.acceptedAt.getTime() - acceptedAt) < 2000,
      "stored acceptedAt matches the server timestamp"
    );

    const again = await jsonRequest(server, {
      method: "POST",
      path: "/auth/me/seller-terms",
      token: signToken({ ...buyer, role: "seller" }),
      body: { termsVersion: "1.0" },
    });
    assert(again.status === 200, "repeat acceptance is allowed");
    const rows = await prisma.sellerTermsAcceptance.count({ where: { userId: buyer.id } });
    assert(rows === 1, "same version is not duplicated");
    const unchanged = await prisma.sellerTermsAcceptance.findUnique({
      where: { userId_termsVersion: { userId: buyer.id, termsVersion: "1.0" } },
    });
    assert(
      unchanged.acceptedAt.getTime() === row.acceptedAt.getTime(),
      "repeat acceptance keeps the original acceptedAt"
    );

    console.log("seller terms acceptance ok");
  } finally {
    server.close();
    if (created.length) {
      await prisma.sellerFssai.deleteMany({ where: { userId: { in: created } } });
      await prisma.sellerTermsAcceptance.deleteMany({ where: { userId: { in: created } } });
      await prisma.user.deleteMany({ where: { id: { in: created } } });
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
