require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const adminRoutes = require("../routes/admin");

const SUPER_PHONE = "+919800000501";
const BUYER_PHONE = "+919800000502";
const CONSOLE_PHONE = "+919800000503";

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
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const superUser = await prisma.user.upsert({
      where: { phone: SUPER_PHONE },
      update: { role: "super_admin", suspended: false, name: "Super" },
      create: { phone: SUPER_PHONE, name: "Super", role: "super_admin" },
    });
    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { role: "buyer", suspended: false, name: "Buyer" },
      create: { phone: BUYER_PHONE, name: "Buyer", role: "buyer" },
    });
    await prisma.user.upsert({
      where: { phone: CONSOLE_PHONE },
      update: { role: "buyer", suspended: false, name: "Future Admin" },
      create: { phone: CONSOLE_PHONE, name: "Future Admin", role: "buyer" },
    });

    const superToken = signToken(superUser);
    const buyerToken = signToken(buyer);

    const forbidden = await jsonRequest(server, {
      method: "GET",
      path: "/admin/dashboard",
      token: buyerToken,
    });
    assert(forbidden.status === 403, "buyer cannot open admin dashboard");

    const grant = await jsonRequest(server, {
      method: "POST",
      path: "/admin/console-admins",
      token: superToken,
      body: { phone: "9800000503" },
    });
    assert(grant.status === 200, `grant failed: ${JSON.stringify(grant.json)}`);
    assert(grant.json.user.role === "admin", "role should be admin");

    const consoleUser = await prisma.user.findUnique({
      where: { phone: CONSOLE_PHONE },
    });
    const consoleToken = signToken(consoleUser);

    const dash = await jsonRequest(server, {
      method: "GET",
      path: "/admin/dashboard",
      token: consoleToken,
    });
    assert(dash.status === 200, "console admin can read dashboard");

    const writeBlocked = await jsonRequest(server, {
      method: "POST",
      path: "/admin/societies",
      token: consoleToken,
      body: { name: "X", city: "Y", inviteCode: "Z" },
    });
    assert(writeBlocked.status === 403, "console admin cannot create society");

    const list = await jsonRequest(server, {
      method: "GET",
      path: "/admin/console-admins",
      token: consoleToken,
    });
    assert(list.status === 403, "console admin cannot list console admins");

    const revoke = await jsonRequest(server, {
      method: "DELETE",
      path: `/admin/console-admins/${consoleUser.id}`,
      token: superToken,
    });
    assert(revoke.status === 200, "revoke failed");

    const after = await prisma.user.findUnique({ where: { phone: CONSOLE_PHONE } });
    assert(after.role === "buyer", "revoked user becomes buyer");

    console.log("console-admins.test.js OK");
  } finally {
    server.close();
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
