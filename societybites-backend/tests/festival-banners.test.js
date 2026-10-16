require("dotenv").config();

const http = require("http");
const express = require("express");
const crypto = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const adminRoutes = require("../routes/admin");
const festivalRoutes = require("../routes/festivalBanners");

const ADMIN_PHONE = "+919800000521";
const BUYER_PHONE = "+919800000522";

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
  app.use("/festival-banners", festivalRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({ error: err.message });
  });
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  const created = { users: [], banners: [] };

  try {
    const admin = await prisma.user.upsert({
      where: { phone: ADMIN_PHONE },
      update: { role: "super_admin", name: "Festival Admin", suspended: false },
      create: {
        phone: ADMIN_PHONE,
        name: "Festival Admin",
        role: "super_admin",
      },
    });
    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { role: "buyer", name: "Festival Buyer", suspended: false },
      create: {
        phone: BUYER_PHONE,
        name: "Festival Buyer",
        role: "buyer",
      },
    });
    created.users.push(admin.id, buyer.id);

    const adminToken = signToken(admin);
    const buyerToken = signToken(buyer);

    const none = await jsonRequest(server, {
      method: "GET",
      path: "/festival-banners/active",
    });
    assert(none.status === 200, "public active endpoint works");
    assert(none.json.banner === null || typeof none.json.banner === "object", "banner payload shape");

    const denied = await jsonRequest(server, {
      method: "POST",
      path: "/admin/festival-banners",
      token: buyerToken,
      body: { name: "Nope", title: "X" },
    });
    assert(denied.status === 403, "buyers cannot create banners");

    const createdBanner = await jsonRequest(server, {
      method: "POST",
      path: "/admin/festival-banners",
      token: adminToken,
      body: {
        name: `Fest ${Date.now()}`,
        title: "Festival Treats",
        subtitle: "From neighbours nearby",
        imageUrl: "https://example.com/festival-banners/demo.jpg",
        placement: "BELOW_SEARCH",
        startsAt: new Date(Date.now() - 86400000).toISOString(),
        endsAt: new Date(Date.now() + 7 * 86400000).toISOString(),
      },
    });
    assert(createdBanner.status === 201, `create failed: ${createdBanner.status}`);
    const id = createdBanner.json.banner.id;
    created.banners.push(id);
    assert(createdBanner.json.banner.status === "DRAFT", "new banners start as draft");

    const stillHidden = await jsonRequest(server, {
      method: "GET",
      path: "/festival-banners/active",
    });
    assert(
      !stillHidden.json.banner || stillHidden.json.banner.id !== id,
      "draft banner is not public"
    );

    const activated = await jsonRequest(server, {
      method: "POST",
      path: `/admin/festival-banners/${id}/activate`,
      token: adminToken,
      body: {},
    });
    assert(activated.status === 200, "activate works");
    assert(activated.json.banner.status === "ACTIVE", "status is active");

    const visible = await jsonRequest(server, {
      method: "GET",
      path: "/festival-banners/active",
    });
    assert(visible.json.banner && visible.json.banner.id === id, "active banner is public");
    assert(visible.json.banner.title === "Festival Treats", "public title matches");

    const second = await jsonRequest(server, {
      method: "POST",
      path: "/admin/festival-banners",
      token: adminToken,
      body: {
        name: `Fest2 ${Date.now()}`,
        title: "Second",
        imageUrl: "https://example.com/festival-banners/two.jpg",
        placement: "BELOW_CATEGORIES",
      },
    });
    assert(second.status === 201, "second banner created");
    created.banners.push(second.json.banner.id);
    await jsonRequest(server, {
      method: "POST",
      path: `/admin/festival-banners/${second.json.banner.id}/activate`,
      token: adminToken,
      body: {},
    });
    const firstAfter = await prisma.festivalBanner.findUnique({ where: { id } });
    assert(firstAfter.status === "INACTIVE", "activating another deactivates the first");

    const deactivated = await jsonRequest(server, {
      method: "POST",
      path: `/admin/festival-banners/${second.json.banner.id}/deactivate`,
      token: adminToken,
      body: {},
    });
    assert(deactivated.status === 200, "deactivate works");
    const cleared = await jsonRequest(server, {
      method: "GET",
      path: "/festival-banners/active",
    });
    assert(cleared.json.banner === null, "no public banner after deactivate");

    console.log("festival banners ok");
  } finally {
    server.close();
    if (created.banners.length) {
      await prisma.festivalBanner.deleteMany({ where: { id: { in: created.banners } } });
    }
    if (created.users.length) {
      await prisma.auditLog.deleteMany({ where: { adminId: { in: created.users } } });
      await prisma.user.deleteMany({ where: { id: { in: created.users } } });
    }
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
