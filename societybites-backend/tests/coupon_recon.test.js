require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const adminRoutes = require("../routes/admin");
const { listCouponSellerPayouts } = require("../lib/couponRecon");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port: addr.port,
        path,
        method,
        headers: {
          Accept: "application/json",
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
    req.end();
  });
}

async function main() {
  const stamp = String(Date.now()).slice(-8);
  const society = await prisma.society.findFirst({ where: { status: "active" } });
  assert(society, "active society required");

  const seller = await prisma.user.create({
    data: {
      phone: `+9177${stamp}11`,
      name: "Recon Seller",
      role: "seller",
      societyId: society.id,
    },
  });
  const buyer = await prisma.user.create({
    data: {
      phone: `+9177${stamp}12`,
      name: "Recon Buyer",
      role: "buyer",
      societyId: society.id,
    },
  });
  const admin = await prisma.user.create({
    data: {
      phone: `+9177${stamp}13`,
      name: "Recon Admin",
      role: "super_admin",
    },
  });

  const listing = await prisma.listing.create({
    data: {
      sellerId: seller.id,
      societyId: society.id,
      name: `Recon dish ${stamp}`,
      price: 500,
      quantity: 5,
      status: "active",
    },
  });

  const coupon = await prisma.coupon.create({
    data: {
      code: `RECON${stamp}`,
      name: "Recon coupon",
      discountType: "FIXED",
      discountValue: 100,
      minimumOrderValue: 0,
      validFrom: new Date(Date.now() - 86400000),
      validUntil: new Date(Date.now() + 86400000),
      audienceType: "ALL",
      status: "ACTIVE",
      fundedBy: "SOCIETYEATS",
    },
  });

  const order = await prisma.order.create({
    data: {
      orderNumber: `RECON-${stamp}`,
      buyerId: buyer.id,
      societyId: society.id,
      subtotal: 500,
      total: 400,
      status: "completed",
      paymentStatus: "paid",
      items: {
        create: [{ listingId: listing.id, quantity: 1, unitPrice: 500 }],
      },
    },
  });

  await prisma.couponRedemption.create({
    data: {
      couponId: coupon.id,
      userId: buyer.id,
      orderId: order.id,
      discountAmount: 100,
      status: "REDEEMED",
      redeemedAt: new Date(),
    },
  });

  const cancelled = await prisma.order.create({
    data: {
      orderNumber: `RECON-C-${stamp}`,
      buyerId: buyer.id,
      societyId: society.id,
      subtotal: 500,
      total: 400,
      status: "cancelled",
      items: {
        create: [{ listingId: listing.id, quantity: 1, unitPrice: 500 }],
      },
    },
  });

  await prisma.couponRedemption.create({
    data: {
      couponId: coupon.id,
      userId: buyer.id,
      orderId: cancelled.id,
      discountAmount: 100,
      status: "REDEEMED",
      redeemedAt: new Date(),
    },
  });

  const app = express();
  app.use(express.json());
  app.use("/admin", adminRoutes);
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  try {
    const report = await listCouponSellerPayouts({ db: prisma });
    const row = report.rows.find((entry) => entry.orderId === order.id);
    assert(row, "includes redeemed order");
    assert(row.subsidyAmount === 100, "subsidy amount");
    assert(row.sellerId === seller.id, "seller id");
    assert(row.foodSubtotal === 500, "food subtotal");
    assert(row.buyerPaid === 400, "buyer paid");
    assert(!report.rows.some((entry) => entry.orderId === cancelled.id), "skips cancelled");

    const bySeller = report.bySeller.find((entry) => entry.sellerId === seller.id);
    assert(bySeller && bySeller.orderCount >= 1, "seller summary");

    const api = await jsonRequest(server, {
      method: "GET",
      path: "/admin/reports/coupon-seller-payouts",
      token: signToken(admin),
    });
    assert(api.status === 200, "admin api");
    assert(api.json.rows.some((entry) => entry.orderNumber === order.orderNumber), "api rows");

    const denied = await jsonRequest(server, {
      method: "GET",
      path: "/admin/reports/coupon-seller-payouts",
      token: signToken(buyer),
    });
    assert(denied.status === 403, "buyer denied");

    console.log("coupon recon ok");
  } finally {
    await prisma.couponRedemption.deleteMany({
      where: { couponId: coupon.id },
    });
    await prisma.order.deleteMany({
      where: { orderNumber: { in: [order.orderNumber, cancelled.orderNumber] } },
    });
    await prisma.listing.delete({ where: { id: listing.id } });
    await prisma.coupon.delete({ where: { id: coupon.id } });
    await prisma.user.deleteMany({
      where: { id: { in: [seller.id, buyer.id, admin.id] } },
    });
    server.close();
    await prisma.$disconnect();
  }
}

main().catch(async (err) => {
  console.error(err);
  try {
    await prisma.$disconnect();
  } catch (_) {}
  process.exit(1);
});
