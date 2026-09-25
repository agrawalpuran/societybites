require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { parseFssaiNumber, assertSellerFssaiUpdate } = require("../lib/fssai");
const authRoutes = require("../routes/auth");
const adminRoutes = require("../routes/admin");

const SELLER_PHONE = "+919800000093";
const BUYER_PHONE = "+919800000094";
const ADMIN_PHONE = "+919800000095";

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
  const parsed = parseFssaiNumber("1234 5678 9012 34");
  assert(parsed === "12345678901234", "strips spaces from 14-digit FSSAI");
  try {
    parseFssaiNumber("12345");
    throw new Error("short number should fail");
  } catch (err) {
    if (err.message === "short number should fail") throw err;
    assert(err.statusCode === 400, "invalid FSSAI is 400");
  }

  const created = { ids: [] };
  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/admin", adminRoutes);
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const seller = await prisma.user.upsert({
      where: { phone: SELLER_PHONE },
      update: { role: "seller", fssaiNumber: null, fssaiExpiry: null, fssaiRegisteredName: null },
      create: { phone: SELLER_PHONE, name: "FSSAI Seller", role: "seller" },
    });
    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { role: "buyer" },
      create: { phone: BUYER_PHONE, name: "FSSAI Buyer", role: "buyer" },
    });
    const admin = await prisma.user.upsert({
      where: { phone: ADMIN_PHONE },
      update: { role: "super_admin" },
      create: { phone: ADMIN_PHONE, name: "FSSAI Admin", role: "super_admin" },
    });
    created.ids.push(seller.id, buyer.id, admin.id);

    const sellerToken = signToken(seller);
    const buyerToken = signToken(buyer);
    const adminToken = signToken(admin);

    const buyerPatch = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: buyerToken,
      body: { fssai: { number: "12345678901234" } },
    });
    assert(buyerPatch.status === 400, "buyer cannot save FSSAI");

    const bad = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { fssai: { number: "abc" } },
    });
    assert(bad.status === 400, "invalid licence rejected");

    const saved = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: {
        fssai: {
          number: "12345678901234",
          registeredName: "Agrawal Kitchen",
          expiry: "2027-12-31",
        },
      },
    });
    assert(saved.status === 200, `seller FSSAI save failed: ${saved.status}`);
    assert(saved.json.user.fssai.number === "12345678901234", "GET/PATCH me returns FSSAI");

    const me = await jsonRequest(server, {
      method: "GET",
      path: "/auth/me",
      token: sellerToken,
    });
    assert(me.status === 200, "GET /auth/me after FSSAI save");
    assert(me.json.fssai && me.json.fssai.number === "12345678901234", "GET me shows saved licence");
    assert(me.json.fssai.registeredName === "Agrawal Kitchen", "GET me shows registered name");

    const fake = await jsonRequest(server, {
      method: "PATCH",
      path: "/auth/me/profile",
      token: sellerToken,
      body: { fssai: { number: "99999999999999" }, userId: buyer.id },
    });
    assert(fake.status === 200, "patch still succeeds for authenticated seller");
    assert(fake.json.user.id === seller.id, "client userId cannot retarget FSSAI");
    assert(fake.json.user.fssai.number === "99999999999999", "updates own record");

    const buyerAdmin = await jsonRequest(server, {
      method: "GET",
      path: "/admin/fssai",
      token: buyerToken,
    });
    assert(buyerAdmin.status === 403, "buyer cannot list admin FSSAI");

    const sellerAdmin = await jsonRequest(server, {
      method: "GET",
      path: "/admin/fssai",
      token: sellerToken,
    });
    assert(sellerAdmin.status === 403, "plain seller cannot list admin FSSAI");

    const unauth = await jsonRequest(server, {
      method: "GET",
      path: "/admin/fssai",
    });
    assert(unauth.status === 401, "unauthenticated admin FSSAI rejected");

    const list = await jsonRequest(server, {
      method: "GET",
      path: "/admin/fssai",
      token: adminToken,
    });
    assert(list.status === 200, "admin can list FSSAI");
    assert(list.json.records.some((row) => row.sellerId === seller.id), "submitted seller is listed");

    const detail = await jsonRequest(server, {
      method: "GET",
      path: `/admin/fssai/${seller.id}`,
      token: adminToken,
    });
    assert(detail.status === 200, "admin can open seller FSSAI");
    assert(detail.json.fssai.number === "99999999999999", "detail has licence");

    assertSellerFssaiUpdate({
      role: "seller",
      number: "",
    });
    console.log("fssai tests passed");
  } finally {
    await prisma.user.deleteMany({ where: { id: { in: created.ids } } }).catch(() => {});
    await new Promise((resolve) => server.close(resolve));
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
