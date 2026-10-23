require("dotenv").config();
const http = require("http");
const express = require("express");
const { randomUUID } = require("crypto");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");
const couponRoutes = require("../routes/coupons");
const { REASONS } = require("../lib/coupons");

const SEED_SELLER_PHONE = "+919901844776";
const SEED_BUYER_PHONE = "+919845154070";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body, headers = {} }) {
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
          ...headers,
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
  const seller = await prisma.user.findUnique({
    where: { phone: SEED_SELLER_PHONE },
  });
  const buyer = await prisma.user.findUnique({
    where: { phone: SEED_BUYER_PHONE },
  });
  assert(seller && seller.societyId && seller.upiId, "seed seller");
  assert(buyer && buyer.societyId === seller.societyId, "seed buyer same society");

  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);
  const stamp = Date.now();
  const listingIds = [];
  const orderIds = [];
  const couponIds = [];

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  app.use("/coupons", couponRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
      code: err.code,
    });
  });
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const created = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Discount dish ${stamp}`,
        price: 200,
        foodType: "VEG",
        category: "Lunch",
        quantity: 20,
        publish: true,
        discountEnabled: true,
        discountPercent: 10,
      },
    });
    assert(created.status === 201, `create ${JSON.stringify(created.json)}`);
    listingIds.push(created.json.id);
    assert(created.json.price === 200, "regular price stored");
    assert(created.json.effectivePrice === 180, "create effective");
    assert(created.json.discountActive === true, "create active");
    assert(created.json.discountEnabled === true, "create enabled");

    const omitted = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${created.json.id}`,
      token: sellerToken,
      body: { description: "still on sale" },
    });
    assert(omitted.status === 200, `patch omit ${JSON.stringify(omitted.json)}`);
    assert(omitted.json.discountEnabled === true, "omit keeps enabled");
    assert(omitted.json.discountPercent === 10, "omit keeps percent");
    assert(omitted.json.price === 200, "omit does not change price");

    const variants = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Discount sizes ${stamp}`,
        price: 80,
        foodType: "VEG",
        category: "Snacks",
        publish: true,
        discountEnabled: true,
        discountPercent: 10,
        variantInventoryMode: "SEPARATE",
        variants: [
          { label: "250 g", price: 80, quantity: 8 },
          { label: "500 g", price: 150, quantity: 8 },
        ],
      },
    });
    assert(variants.status === 201, `variants ${JSON.stringify(variants.json)}`);
    listingIds.push(variants.json.id);
    const siblings = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${variants.json.id}/variants`,
      token: sellerToken,
    });
    assert(siblings.status === 200, "variant siblings");
    assert(siblings.json.length === 2, "two sizes");
    const cheap = siblings.json.find((row) => row.price === 80);
    const dear = siblings.json.find((row) => row.price === 150);
    assert(cheap && dear, "both sizes");
    assert(cheap.effectivePrice === 72, "cheap size 10%");
    assert(dear.effectivePrice === 135, "dear size 10%");
    listingIds.push(cheap.id, dear.id);

    const shared = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Discount pool ${stamp}`,
        price: 80,
        foodType: "VEG",
        category: "Snacks",
        publish: true,
        discountEnabled: true,
        discountPercent: 10,
        variantInventoryMode: "SHARED",
        sharedPoolQuantity: 1000,
        sharedPoolUnit: "g",
        variants: [
          { label: "250 g", price: 80, portionAmount: 250, portionUnit: "grams" },
          { label: "500 g", price: 150, portionAmount: 500, portionUnit: "grams" },
        ],
      },
    });
    assert(shared.status === 201, `shared ${JSON.stringify(shared.json)}`);
    listingIds.push(shared.json.id);
    const poolBefore = shared.json.poolQuantity;

    const placed = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: created.json.id, quantity: 2 }],
      },
    });
    assert(placed.status === 201 || placed.status === 200, `order ${JSON.stringify(placed.json)}`);
    orderIds.push(placed.json.id);
    assert(placed.json.subtotal === 360, `subtotal ${placed.json.subtotal}`);
    const line = placed.json.items[0];
    assert(line.unitPrice === 180, "charged unit");
    assert(line.originalUnitPrice === 200, "original snapshot");
    assert(line.discountPercent === 10, "percent snapshot");

    const disabled = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${created.json.id}`,
      token: sellerToken,
      body: { discountEnabled: false },
    });
    assert(disabled.status === 200, "disable");
    assert(disabled.json.price === 200, "disable keeps regular price");
    assert(disabled.json.effectivePrice === 200, "disable effective");
    assert(disabled.json.discountActive === false, "disable inactive");

    const later = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: created.json.id, quantity: 1 }],
      },
    });
    assert(later.status === 201 || later.status === 200, `later ${JSON.stringify(later.json)}`);
    orderIds.push(later.json.id);
    assert(later.json.subtotal === 200, "new order uses full price");
    assert(later.json.items[0].unitPrice === 200, "new unit full");
    assert(later.json.items[0].discountPercent == null, "new order no percent");

    const old = await prisma.orderItem.findFirst({
      where: { orderId: placed.json.id },
    });
    assert(old.unitPrice === 180, "old snapshot unit");
    assert(old.originalUnitPrice === 200, "old snapshot original");
    assert(old.discountPercent === 10, "old snapshot percent");

    const couponListing = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Discount coupon ${stamp}`,
        price: 400,
        foodType: "VEG",
        category: "Lunch",
        quantity: 20,
        publish: true,
        discountEnabled: true,
        discountPercent: 50,
      },
    });
    assert(couponListing.status === 201, `coupon listing ${JSON.stringify(couponListing.json)}`);
    listingIds.push(couponListing.json.id);
    assert(couponListing.json.effectivePrice === 200, "50% of 400");

    const couponCode = `LD${String(stamp).slice(-6)}`;
    const coupon = await prisma.coupon.create({
      data: {
        code: couponCode,
        name: couponCode,
        discountType: "FIXED",
        discountValue: 50,
        minimumOrderValue: 300,
        validFrom: new Date(Date.now() - 86400000),
        validUntil: new Date(Date.now() + 86400000),
        audienceType: "ALL",
        status: "ACTIVE",
        fundedBy: "SOCIETYEATS",
      },
    });
    couponIds.push(coupon.id);

    const tooSmall = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        couponCode,
        items: [{ listingId: couponListing.json.id, quantity: 1 }],
      },
    });
    assert(tooSmall.status === 400, "coupon min uses discounted subtotal (200 < 300, regular 400 would pass)");
    assert(
      tooSmall.json.code === REASONS.MINIMUM_ORDER_NOT_MET ||
        String(tooSmall.json.error || "").toLowerCase().includes("minimum"),
      `min-order error ${JSON.stringify(tooSmall.json)}`
    );

    const withCoupon = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        couponCode,
        items: [{ listingId: couponListing.json.id, quantity: 2 }],
      },
    });
    assert(
      withCoupon.status === 201 || withCoupon.status === 200,
      `coupon order ${JSON.stringify(withCoupon.json)}`
    );
    orderIds.push(withCoupon.json.id);
    assert(withCoupon.json.subtotal === 400, "coupon food subtotal is 2 × 200");
    assert(withCoupon.json.couponDiscount === 50, "coupon amount");
    assert(withCoupon.json.total === withCoupon.json.subtotal + withCoupon.json.communityFee - 50,
      "total after coupon");

    const sharedOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: shared.json.id, quantity: 1 }],
      },
    });
    assert(
      sharedOrder.status === 201 || sharedOrder.status === 200,
      `shared order ${JSON.stringify(sharedOrder.json)}`
    );
    orderIds.push(sharedOrder.json.id);
    assert(sharedOrder.json.items[0].unitPrice === 72, "shared size charged sale");
    const poolAfter = await prisma.listing.findUnique({
      where: { id: shared.json.id },
    });
    assert(poolAfter.portionUnits === 250 || poolAfter.portionUnits == null || poolAfter.portionUnits === shared.json.portionUnits,
      "portion units not rewritten by discount");
    assert(poolAfter.quantity < poolBefore, "shared pool still decrements");

    const key = randomUUID();
    const first = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: created.json.id, quantity: 1 }],
      },
      headers: { "Idempotency-Key": key },
    });
    assert(first.status === 201 || first.status === 200, `idem first ${JSON.stringify(first.json)}`);
    orderIds.push(first.json.id);
    const firstUnit = first.json.items[0].unitPrice;
    await prisma.listing.update({
      where: { id: created.json.id },
      data: { discountEnabled: false },
    });
    const replay = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: created.json.id, quantity: 1 }],
      },
      headers: { "Idempotency-Key": key },
    });
    assert(replay.status === first.status, "idem replay status");
    assert(replay.json.id === first.json.id, "idem same order");
    assert(replay.json.items[0].unitPrice === firstUnit, "idem keeps snapshot");

    console.log("listing-discount-api.test.js ok");
  } finally {
    await new Promise((resolve) => server.close(resolve));
    if (orderIds.length) {
      await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } });
      await prisma.couponRedemption.deleteMany({ where: { orderId: { in: orderIds } } });
      await prisma.orderIdempotency.deleteMany({ where: { orderId: { in: orderIds } } }).catch(() => {});
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    }
    if (couponIds.length) {
      await prisma.couponRedemption.deleteMany({ where: { couponId: { in: couponIds } } });
      await prisma.coupon.deleteMany({ where: { id: { in: couponIds } } });
    }
    const uniqueListingIds = [...new Set(listingIds.filter(Boolean))];
    if (uniqueListingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: uniqueListingIds } } });
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
