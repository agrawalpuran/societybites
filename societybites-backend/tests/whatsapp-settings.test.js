require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const adminRoutes = require("../routes/admin");
const settingsRoutes = require("../routes/settings");
const {
  WHATSAPP_ORDER_NOTIFICATIONS_KEY,
  isWhatsAppOrderNotificationsEnabled,
  setWhatsAppOrderNotifications,
} = require("../lib/whatsappSetting");

const BUYER_PHONE = "+919800000401";
const SELLER_PHONE = "+919800000402";
const ADMIN_PHONE = "+919800000403";

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
  const settingBefore = await prisma.appSetting.findUnique({
    where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
  });
  const feeBefore = await prisma.appSetting.findUnique({
    where: { key: "platform_fee" },
  });

  const app = express();
  app.use(express.json());
  app.use("/admin", adminRoutes);
  app.use("/settings", settingsRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({ error: err.message });
  });
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  const created = { users: [] };

  try {
    await prisma.appSetting.deleteMany({
      where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
    });

    const society = await prisma.society.findFirst();
    assert(society, "seed society required");

    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { role: "buyer", societyId: society.id, consoleAdmin: false },
      create: {
        phone: BUYER_PHONE,
        name: "WA Settings Buyer",
        role: "buyer",
        societyId: society.id,
      },
    });
    const seller = await prisma.user.upsert({
      where: { phone: SELLER_PHONE },
      update: { role: "seller", societyId: society.id, consoleAdmin: false },
      create: {
        phone: SELLER_PHONE,
        name: "WA Settings Seller",
        role: "seller",
        societyId: society.id,
        upiId: "wa-seller@oksbi",
        paymentEnabled: true,
      },
    });
    const admin = await prisma.user.upsert({
      where: { phone: ADMIN_PHONE },
      update: { role: "super_admin", societyId: society.id, consoleAdmin: true },
      create: {
        phone: ADMIN_PHONE,
        name: "WA Settings Admin",
        role: "super_admin",
        societyId: society.id,
        consoleAdmin: true,
      },
    });
    created.users.push(buyer.id, seller.id, admin.id);

    const buyerToken = signToken(buyer);
    const sellerToken = signToken(seller);
    const adminToken = signToken(admin);

    assert(
      (await isWhatsAppOrderNotificationsEnabled()) === false,
      "missing setting is off"
    );

    const missing = await jsonRequest(server, {
      method: "GET",
      path: "/admin/settings",
      token: adminToken,
    });
    assert(missing.status === 200, "admin GET settings");
    assert(
      missing.json.whatsappOrderNotifications === false,
      "GET false when missing"
    );
    assert(typeof missing.json.platformFee === "number", "platform fee still returned");
    assert(
      typeof missing.json.fssaiSellingRequirement === "boolean",
      "fssai setting still returned"
    );

    const publicSettings = await jsonRequest(server, {
      method: "GET",
      path: "/settings",
    });
    assert(publicSettings.status === 200, "public settings");
    assert(
      publicSettings.json.whatsappOrderNotifications === undefined,
      "public GET /settings hides WhatsApp flag"
    );

    const buyerPatch = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: buyerToken,
      body: { whatsappOrderNotifications: true },
    });
    assert(buyerPatch.status === 403, "buyer 403");

    const sellerPatch = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: sellerToken,
      body: { whatsappOrderNotifications: true },
    });
    assert(sellerPatch.status === 403, "seller 403");
    assert(
      (await isWhatsAppOrderNotificationsEnabled()) === false,
      "403 does not enable setting"
    );

    const enable = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: adminToken,
      body: { whatsappOrderNotifications: true },
    });
    assert(enable.status === 200, `admin enable ${enable.status}`);
    assert(enable.json.whatsappOrderNotifications === true, "PATCH true");
    const storedOn = await prisma.appSetting.findUnique({
      where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
    });
    assert(storedOn && storedOn.value === "on", "persists on");

    const afterOn = await jsonRequest(server, {
      method: "GET",
      path: "/admin/settings",
      token: adminToken,
    });
    assert(afterOn.json.whatsappOrderNotifications === true, "GET saved true");

    const auditOn = await prisma.auditLog.findFirst({
      where: {
        adminId: admin.id,
        action: "UPDATE_WHATSAPP_ORDER_NOTIFICATIONS",
      },
      orderBy: { createdAt: "desc" },
    });
    assert(auditOn, "audit on");
    const onDetails = JSON.parse(auditOn.details);
    assert(onDetails.whatsappOrderNotifications === true, "audit new true");
    assert(
      onDetails.whatsappOrderNotificationsPrevious === false,
      "audit previous false"
    );

    const feeValue = missing.json.platformFee;
    const feePatch = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: adminToken,
      body: { platformFee: feeValue },
    });
    assert(feePatch.status === 200, "platform fee still patchable");
    assert(feePatch.json.platformFee === feeValue, "fee unchanged");
    assert(
      feePatch.json.whatsappOrderNotifications === true,
      "whatsapp remains on after fee patch"
    );

    const fssaiValue = missing.json.fssaiSellingRequirement;
    const fssaiPatch = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: adminToken,
      body: { fssaiSellingRequirement: fssaiValue },
    });
    assert(fssaiPatch.status === 200, "fssai still patchable");
    assert(
      fssaiPatch.json.fssaiSellingRequirement === fssaiValue,
      "fssai preserved"
    );

    const disable = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: adminToken,
      body: { whatsappOrderNotifications: false },
    });
    assert(disable.status === 200, "admin disable");
    assert(disable.json.whatsappOrderNotifications === false, "PATCH false");
    const storedOff = await prisma.appSetting.findUnique({
      where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
    });
    assert(storedOff && storedOff.value === "off", "persists off");

    const afterOff = await jsonRequest(server, {
      method: "GET",
      path: "/admin/settings",
      token: adminToken,
    });
    assert(afterOff.json.whatsappOrderNotifications === false, "GET saved false");

    const auditOff = await prisma.auditLog.findFirst({
      where: {
        adminId: admin.id,
        action: "UPDATE_WHATSAPP_ORDER_NOTIFICATIONS",
      },
      orderBy: { createdAt: "desc" },
    });
    assert(auditOff, "audit off");
    const offDetails = JSON.parse(auditOff.details);
    assert(offDetails.whatsappOrderNotifications === false, "audit new false");
    assert(
      offDetails.whatsappOrderNotificationsPrevious === true,
      "audit previous true"
    );

    await setWhatsAppOrderNotifications(false);
    console.log("whatsapp-settings.test.js passed");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (settingBefore) {
      await prisma.appSetting.upsert({
        where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
        update: { value: settingBefore.value },
        create: {
          key: WHATSAPP_ORDER_NOTIFICATIONS_KEY,
          value: settingBefore.value,
        },
      });
    } else {
      await prisma.appSetting.deleteMany({
        where: { key: WHATSAPP_ORDER_NOTIFICATIONS_KEY },
      });
    }
    if (feeBefore) {
      await prisma.appSetting.upsert({
        where: { key: "platform_fee" },
        update: { value: feeBefore.value },
        create: { key: "platform_fee", value: feeBefore.value },
      });
    }
    await prisma.auditLog.deleteMany({
      where: { adminId: { in: created.users } },
    });
    if (created.users.length) {
      await prisma.refreshToken.deleteMany({
        where: { userId: { in: created.users } },
      });
      await prisma.user.deleteMany({ where: { id: { in: created.users } } });
    }
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
