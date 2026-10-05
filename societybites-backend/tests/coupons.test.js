require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { REASONS, validateCoupon, applyCoupon, startOfIstDay, startOfIstWeek, startOfIstMonth } = require("../lib/coupons");
const couponRoutes = require("../routes/coupons");
const adminRoutes = require("../routes/admin");

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

async function makeCoupon(code, overrides = {}) {
  const now = new Date();
  return prisma.coupon.create({
    data: {
      code,
      name: code,
      discountType: "FIXED",
      discountValue: 100,
      minimumOrderValue: 300,
      validFrom: new Date(now.getTime() - 86400000),
      validUntil: new Date(now.getTime() + 86400000),
      audienceType: "ALL",
      status: "ACTIVE",
      fundedBy: "SOCIETYEATS",
      ...overrides,
    },
  });
}

async function redeem(couponId, userId, discountAmount, when) {
  return prisma.couponRedemption.create({
    data: {
      couponId,
      userId,
      discountAmount,
      status: "REDEEMED",
      appliedAt: when,
      redeemedAt: when,
    },
  });
}

async function main() {
  const stamp = String(Date.now()).slice(-8);
  const buyer = await prisma.user.create({
    data: { phone: `+9177${stamp}01`, name: "Coupon Buyer", role: "buyer" },
  });
  const other = await prisma.user.create({
    data: { phone: `+9177${stamp}02`, name: "Coupon Other", role: "buyer" },
  });
  const admin = await prisma.user.create({
    data: { phone: `+9177${stamp}03`, name: "Coupon Admin", role: "super_admin" },
  });
  const codes = [];

  const app = express();
  app.use(express.json());
  app.use("/coupons", couponRoutes);
  app.use("/admin", adminRoutes);
  app.use((err, _req, res, _next) => {
    res.status(err.statusCode || 500).json({ error: err.statusCode ? err.message : "Internal server error" });
  });
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  try {
    const fixed = await makeCoupon(`WELCOME${stamp}`);
    codes.push(fixed.code);
    const ok = await validateCoupon({ code: `welcome${stamp}`, userId: buyer.id, orderSubtotal: 500 });
    assert(ok.valid === true, "valid coupon");
    assert(ok.discountAmount === 100, "discount is 100");
    assert(ok.buyerPayable === 400, "buyer pays 400");
    assert(ok.sellerGrossAmount === 500, "seller gross stays 500");
    assert(ok.societyEatsSubsidy === 100, "SocietyEats subsidy equals the discount");
    assert(ok.code === fixed.code, "code match is case-insensitive");

    const low = await validateCoupon({ code: fixed.code, userId: buyer.id, orderSubtotal: 299 });
    assert(low.reason === REASONS.MINIMUM_ORDER_NOT_MET, "minimum order");
    assert(low.minimumOrderValue === 300, "minimum order value returned");
    assert(low.orderSubtotal === 299, "order subtotal echoed");

    const expired = await makeCoupon(`EXP${stamp}`, {
      validFrom: new Date(Date.now() - 5 * 86400000),
      validUntil: new Date(Date.now() - 86400000),
    });
    codes.push(expired.code);
    assert((await validateCoupon({ code: expired.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.COUPON_EXPIRED, "expired");

    const future = await makeCoupon(`SOON${stamp}`, {
      validFrom: new Date(Date.now() + 86400000),
      validUntil: new Date(Date.now() + 5 * 86400000),
    });
    codes.push(future.code);
    assert((await validateCoupon({ code: future.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.COUPON_NOT_STARTED, "not started");

    const paused = await makeCoupon(`PAUSE${stamp}`, { status: "PAUSED" });
    codes.push(paused.code);
    assert((await validateCoupon({ code: paused.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.COUPON_PAUSED, "paused");

    const capped = await makeCoupon(`CAP${stamp}`, { totalUsageLimit: 1, minimumOrderValue: 0 });
    codes.push(capped.code);
    await redeem(capped.id, other.id, 100, new Date());
    assert((await validateCoupon({ code: capped.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.USAGE_LIMIT_REACHED, "total usage");

    const once = await makeCoupon(`ONCE${stamp}`, { usagePerBuyerLimit: 1, usageFrequency: "ONCE", minimumOrderValue: 0 });
    codes.push(once.code);
    await redeem(once.id, buyer.id, 100, new Date());
    assert((await validateCoupon({ code: once.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.BUYER_USAGE_LIMIT_REACHED, "buyer limit");

    const daily = await makeCoupon(`DAY${stamp}`, { usageFrequency: "DAILY", minimumOrderValue: 0 });
    codes.push(daily.code);
    await redeem(daily.id, buyer.id, 100, new Date(startOfIstDay(new Date()).getTime() - 3600000));
    assert((await validateCoupon({ code: daily.code, userId: buyer.id, orderSubtotal: 500 })).valid, "previous day does not block");
    await redeem(daily.id, buyer.id, 100, new Date());
    assert((await validateCoupon({ code: daily.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.BUYER_USAGE_LIMIT_REACHED, "daily");

    const weekly = await makeCoupon(`WEEK${stamp}`, { usageFrequency: "WEEKLY", minimumOrderValue: 0 });
    codes.push(weekly.code);
    await redeem(weekly.id, buyer.id, 100, new Date(startOfIstWeek(new Date()).getTime() - 3600000));
    assert((await validateCoupon({ code: weekly.code, userId: buyer.id, orderSubtotal: 500 })).valid, "previous week does not block");
    await redeem(weekly.id, buyer.id, 100, new Date());
    assert((await validateCoupon({ code: weekly.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.BUYER_USAGE_LIMIT_REACHED, "weekly");

    const monthly = await makeCoupon(`MONTH${stamp}`, { usageFrequency: "MONTHLY", minimumOrderValue: 0 });
    codes.push(monthly.code);
    await redeem(monthly.id, buyer.id, 100, new Date(startOfIstMonth(new Date()).getTime() - 3600000));
    assert((await validateCoupon({ code: monthly.code, userId: buyer.id, orderSubtotal: 500 })).valid, "previous month does not block");
    await redeem(monthly.id, buyer.id, 100, new Date());
    assert((await validateCoupon({ code: monthly.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.BUYER_USAGE_LIMIT_REACHED, "monthly");

    const selected = await makeCoupon(`SEL${stamp}`, { audienceType: "SELECTED_USERS", minimumOrderValue: 0 });
    codes.push(selected.code);
    await prisma.couponEligibleUser.create({ data: { couponId: selected.id, userId: buyer.id } });
    assert((await validateCoupon({ code: selected.code, userId: buyer.id, orderSubtotal: 500 })).valid, "selected user allowed");
    assert((await validateCoupon({ code: selected.code, userId: other.id, orderSubtotal: 500 })).reason === REASONS.NOT_ELIGIBLE, "selected user rejected");

    const small = await makeCoupon(`SMALL${stamp}`, { discountValue: 100, minimumOrderValue: 0 });
    codes.push(small.code);
    const cappedDiscount = await validateCoupon({ code: small.code, userId: buyer.id, orderSubtotal: 80 });
    assert(cappedDiscount.discountAmount === 80, "discount cannot exceed subtotal");
    assert(cappedDiscount.buyerPayable === 0, "buyer payable floors at zero");
    assert(cappedDiscount.sellerGrossAmount === 80, "seller gross stays the subtotal");
    assert(cappedDiscount.societyEatsSubsidy === 80, "subsidy matches the capped discount");

    const budget = await makeCoupon(`BUDGET${stamp}`, { campaignBudget: 100, minimumOrderValue: 0 });
    codes.push(budget.code);
    await redeem(budget.id, other.id, 100, new Date());
    assert((await validateCoupon({ code: budget.code, userId: buyer.id, orderSubtotal: 500 })).reason === REASONS.COUPON_EXHAUSTED, "campaign budget");

    const open = await makeCoupon(`OPEN${stamp}`, { totalUsageLimit: 1, minimumOrderValue: 0 });
    codes.push(open.code);
    await prisma.couponRedemption.create({
      data: { couponId: open.id, userId: buyer.id, discountAmount: 100, status: "APPLIED" },
    });
    assert((await validateCoupon({ code: open.code, userId: buyer.id, orderSubtotal: 500 })).valid, "applied does not count");
    await prisma.couponRedemption.updateMany({
      where: { couponId: open.id },
      data: { status: "REVERSED", reversedAt: new Date() },
    });
    assert((await validateCoupon({ code: open.code, userId: buyer.id, orderSubtotal: 500 })).valid, "reversed does not count");

    const society = await prisma.society.findFirst({ where: { status: "active" } });
    assert(society, "a society is required for the order coupon guard");
    const order = await prisma.order.create({
      data: {
        orderNumber: `COUPON-${stamp}`,
        buyerId: buyer.id,
        societyId: society.id,
        subtotal: 500,
        total: 500,
      },
    });
    const first = await applyCoupon({
      code: open.code,
      userId: buyer.id,
      orderSubtotal: 500,
      orderId: order.id,
    });
    assert(first.valid === true, "first coupon can be reserved");
    const second = await applyCoupon({
      code: fixed.code,
      userId: buyer.id,
      orderSubtotal: 500,
      orderId: order.id,
    });
    assert(second.reason === REASONS.COUPON_ALREADY_APPLIED, "one coupon per order");

    const unauth = await jsonRequest(server, {
      method: "POST",
      path: "/coupons/validate",
      body: { code: fixed.code, orderSubtotal: 500 },
    });
    assert(unauth.status === 401, "validation requires the existing session");

    const ignoredUser = await jsonRequest(server, {
      method: "POST",
      path: "/coupons/validate",
      token: signToken(buyer),
      body: { code: selected.code, orderSubtotal: 500, userId: other.id },
    });
    assert(ignoredUser.status === 200 && ignoredUser.json.valid === true, "body userId is ignored");

    const created = await jsonRequest(server, {
      method: "POST",
      path: "/admin/coupons",
      token: signToken(admin),
      body: {
        code: `admin${stamp}`,
        name: "Admin coupon",
        discountType: "FIXED",
        discountValue: 50,
        minimumOrderValue: 200,
        validFrom: new Date(Date.now() - 1000).toISOString(),
        validUntil: new Date(Date.now() + 86400000).toISOString(),
        totalUsageLimit: 10,
        usagePerBuyerLimit: 1,
        audienceType: "ALL",
        status: "ACTIVE",
      },
    });
    assert(created.status === 201, `admin can create ${created.status}`);
    codes.push(created.json.code);
    assert(created.json.fundedBy === "SOCIETYEATS", "funding source is SocietyEats");
    assert(created.json.sellerGrossAmount === undefined, "list payload has no checkout quote");
    const listed = await jsonRequest(server, {
      method: "GET",
      path: "/admin/coupons",
      token: signToken(admin),
    });
    assert(listed.json.coupons.some((row) => row.code === created.json.code && row.totalUsage === 0), "admin list includes usage");

    const buyerAdmin = await jsonRequest(server, {
      method: "POST",
      path: "/admin/coupons",
      token: signToken(buyer),
      body: { code: "NOPE" },
    });
    assert(buyerAdmin.status === 403, "buyers cannot create coupons");

    console.log("coupons ok");
  } finally {
    const coupons = await prisma.coupon.findMany({
      where: { code: { in: codes } },
      select: { id: true },
    });
    const couponIds = coupons.map((row) => row.id);
    await prisma.couponRedemption.deleteMany({ where: { couponId: { in: couponIds } } });
    await prisma.couponEligibleUser.deleteMany({ where: { couponId: { in: couponIds } } });
    await prisma.order.deleteMany({ where: { orderNumber: `COUPON-${stamp}` } });
    await prisma.coupon.deleteMany({ where: { id: { in: couponIds } } });
    await prisma.user.deleteMany({ where: { id: { in: [buyer.id, other.id, admin.id] } } });
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
