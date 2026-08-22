require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");
const listingRoutes = require("../routes/listings");
const campaignRoutes = require("../routes/preorderCampaigns");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";
const BUYER2_PHONE = "+919111000001";
const OTHER_SELLER_PHONE = "+919111000002";

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function jsonRequest(server, { method, path, token, body }) {
  const addr = server.address();
  return new Promise((resolve, reject) => {
    const payload = body ? Buffer.from(JSON.stringify(body)) : null;
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

function futureDates() {
  const orderOpenAt = new Date(Date.now() - 60 * 1000);
  const orderCutoffAt = new Date(Date.now() + 60 * 60 * 1000);
  const fulfilmentAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
  return { orderOpenAt, orderCutoffAt, fulfilmentAt };
}

function qty(summary, name) {
  return summary.products.find((p) => p.productName === name)?.quantityToPrepare;
}

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const leftoverCampaigns = await prisma.preOrderCampaign.findMany({
    where: { title: { startsWith: "Test Seller Dashboard" } },
    select: { id: true },
  });
  if (leftoverCampaigns.length) {
    await prisma.order.deleteMany({
      where: { campaignId: { in: leftoverCampaigns.map((c) => c.id) } },
    });
    await prisma.preOrderCampaign.deleteMany({
      where: { id: { in: leftoverCampaigns.map((c) => c.id) } },
    });
  }

  const buyer2 = await prisma.user.upsert({
    where: { phone: BUYER2_PHONE },
    update: {
      name: "Test Buyer Two",
      role: "buyer",
      societyId: seller.societyId,
      suspended: false,
    },
    create: {
      phone: BUYER2_PHONE,
      name: "Test Buyer Two",
      role: "buyer",
      societyId: seller.societyId,
    },
  });

  const otherSeller = await prisma.user.upsert({
    where: { phone: OTHER_SELLER_PHONE },
    update: {
      name: "Test Other Seller",
      role: "seller",
      societyId: seller.societyId,
      upiId: "other.seller@oksbi",
      paymentEnabled: true,
      suspended: false,
    },
    create: {
      phone: OTHER_SELLER_PHONE,
      name: "Test Other Seller",
      role: "seller",
      societyId: seller.societyId,
      upiId: "other.seller@oksbi",
      paymentEnabled: true,
    },
  });

  const buyerToken = signToken(buyer);
  const buyer2Token = signToken(buyer2);
  const sellerToken = signToken(seller);
  const otherSellerToken = signToken(otherSeller);

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/preorder-campaigns", campaignRoutes);
  app.use("/orders", orderRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({
      error: statusCode === 500 ? "Internal server error" : err.message,
    });
  });

  const server = await new Promise((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });

  const created = { campaignIds: [], orderIds: [], listingIds: [] };

  try {
    const dates = futureDates();
    const createdCampaign = await jsonRequest(server, {
      method: "POST",
      path: "/preorder-campaigns",
      token: sellerToken,
      body: {
        title: `Test Seller Dashboard ${Date.now()}`,
        orderOpenAt: dates.orderOpenAt.toISOString(),
        orderCutoffAt: dates.orderCutoffAt.toISOString(),
        fulfilmentAt: dates.fulfilmentAt.toISOString(),
        status: "open",
        offeredFulfilmentMethods: ["pickup", "seller_delivery"],
        defaultDeliveryCharge: 40,
        coverImageUrl: "/uploads/test-preorder-cover.jpg",
        products: [
          { name: "Samosa", price: 20, inventoryMode: "demand" },
          { name: "Kachori", price: 25, inventoryMode: "demand" },
          { name: "Dhokla", price: 30, inventoryMode: "limited", quantity: 10 },
        ],
      },
    });
    assert(
      createdCampaign.status === 201,
      `campaign create failed: ${createdCampaign.status}`
    );
    const campaign = createdCampaign.json;
    created.campaignIds.push(campaign.id);
    assert(
      campaign.coverImageUrl === "/uploads/test-preorder-cover.jpg",
      "create response cover image"
    );
    const samosa = campaign.products.find((p) => p.name === "Samosa");
    const kachori = campaign.products.find((p) => p.name === "Kachori");
    const dhokla = campaign.products.find((p) => p.name === "Dhokla");

    const otherSellerCoverPatch = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}`,
      token: otherSellerToken,
      body: { coverImageUrl: "/uploads/not-allowed.jpg" },
    });
    assert(
      otherSellerCoverPatch.status === 403,
      "another seller cannot update campaign cover"
    );

    const coverPatch = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}`,
      token: sellerToken,
      body: { coverImageUrl: "/uploads/replaced-preorder-cover.webp" },
    });
    assert(coverPatch.status === 200, "campaign cover update failed");
    assert(
      coverPatch.json.coverImageUrl === "/uploads/replaced-preorder-cover.webp",
      "updated cover image response"
    );

    const listWithCover = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns?societyId=${encodeURIComponent(seller.societyId)}`,
    });
    assert(listWithCover.status === 200, "campaign list failed");
    assert(
      listWithCover.json.find((item) => item.id === campaign.id)?.coverImageUrl ===
        "/uploads/replaced-preorder-cover.webp",
      "campaign list cover image"
    );

    const regularListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Regular dashboard ${Date.now()}`,
        price: 50,
        quantity: 5,
        status: "active",
      },
    });
    created.listingIds.push(regularListing.id);

    const orderA = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "pickup",
        paymentMethod: "upi",
        items: [
          { listingId: samosa.id, quantity: 3 },
          { listingId: kachori.id, quantity: 1 },
        ],
      },
    });
    assert(orderA.status === 201, `order A failed: ${JSON.stringify(orderA.json)}`);
    created.orderIds.push(orderA.json.id);

    const orderB = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyer2Token,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "seller_delivery",
        paymentMethod: "cash",
        items: [
          { listingId: samosa.id, quantity: 2 },
          { listingId: dhokla.id, quantity: 1 },
        ],
      },
    });
    assert(orderB.status === 201, `order B failed: ${JSON.stringify(orderB.json)}`);
    created.orderIds.push(orderB.json.id);

    const orderCancelled = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "pickup",
        items: [{ listingId: kachori.id, quantity: 4 }],
      },
    });
    assert(orderCancelled.status === 201, "cancelled-source order failed");
    created.orderIds.push(orderCancelled.json.id);
    const cancelRes = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${orderCancelled.json.id}/status`,
      token: buyerToken,
      body: { status: "cancelled" },
    });
    assert(cancelRes.status === 200, "cancel failed");

    const regularOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: regularListing.id, quantity: 2 }],
      },
    });
    assert(regularOrder.status === 201, "regular order failed");
    created.orderIds.push(regularOrder.json.id);

    const unauth = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.id}/summary`,
    });
    assert(unauth.status === 401, "summary must require auth");

    const buyerSummary = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.id}/summary`,
      token: buyerToken,
    });
    assert(buyerSummary.status === 403, "buyer must not access seller summary");

    const otherSummary = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.id}/summary`,
      token: otherSellerToken,
    });
    assert(otherSummary.status === 403, "another seller must not access summary");

    const missing = await jsonRequest(server, {
      method: "GET",
      path: "/preorder-campaigns/does-not-exist/summary",
      token: sellerToken,
    });
    assert(missing.status === 404, "unknown campaign summary must 404");

    const summaryRes = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.id}/summary`,
      token: sellerToken,
    });
    assert(summaryRes.status === 200, `summary failed: ${JSON.stringify(summaryRes.json)}`);
    const summary = summaryRes.json;

    assert(summary.campaignId === campaign.id, "campaignId mismatch");
    assert(summary.title === campaign.title, "title mismatch");
    assert(
      summary.coverImageUrl === "/uploads/replaced-preorder-cover.webp",
      "summary cover image"
    );
    assert(summary.status === "open", "status should remain open");
    assert(summary.totalOrders === 2, `expected 2 valid orders, got ${summary.totalOrders}`);
    assert(summary.totalItems === 7, `expected 7 items, got ${summary.totalItems}`);
    assert(summary.foodSubtotal === 155, `expected foodSubtotal 155, got ${summary.foodSubtotal}`);
    assert(summary.fulfilment.pickup === 1, "pickup breakdown");
    assert(summary.fulfilment.seller_delivery === 1, "seller_delivery breakdown");
    assert(summary.products.length === 3, "all campaign products should appear");
    assert(qty(summary, "Samosa") === 5, `samosa qty ${qty(summary, "Samosa")}`);
    assert(qty(summary, "Kachori") === 1, `kachori qty ${qty(summary, "Kachori")}`);
    assert(qty(summary, "Dhokla") === 1, `dhokla qty ${qty(summary, "Dhokla")}`);

    const demandListing = await prisma.listing.findUnique({ where: { id: samosa.id } });
    assert(
      demandListing.quantity === 0,
      "demand listing.quantity must not be used as production total"
    );
    assert(qty(summary, "Samosa") !== demandListing.quantity, "must aggregate OrderItems");

    const ordersRes = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.id}/orders`,
      token: sellerToken,
    });
    assert(ordersRes.status === 200, "campaign orders failed");
    const campaignOrders = ordersRes.json;
    assert(campaignOrders.length === 3, "list includes cancelled campaign orders, excludes regular");
    assert(
      campaignOrders.every((o) => o.type === "pre_order" && o.campaignId === campaign.id),
      "orders must be this campaign only"
    );
    assert(
      !campaignOrders.some((o) => o.id === regularOrder.json.id),
      "regular orders must be excluded from campaign order list"
    );

    const listed = campaignOrders.find((o) => o.id === orderB.json.id);
    assert(listed, "buyer 2 order missing");
    assert(listed.orderNumber, "order number required");
    assert(listed.buyerName === "Test Buyer Two", "buyer name");
    assert(listed.buyerPhone === BUYER2_PHONE, "buyer phone as in seller order flow");
    assert(listed.items.length === 2, "multi-product items");
    assert(listed.subtotal === 70, "food subtotal on order");
    assert(listed.deliveryCharge === 40, "delivery charge on order");
    assert(listed.total === listed.subtotal + listed.communityFee + listed.deliveryCharge, "total");
    assert(listed.fulfilmentMethod === "seller_delivery", "fulfilment method");
    assert(listed.status, "order status");
    assert(listed.paymentStatus, "payment status");

    const otherOrders = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.id}/orders`,
      token: otherSellerToken,
    });
    assert(otherOrders.status === 403, "another seller cannot list campaign orders");

    const removeCover = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}`,
      token: sellerToken,
      body: { coverImageUrl: null },
    });
    assert(removeCover.status === 200, "campaign cover removal failed");
    assert(removeCover.json.coverImageUrl === null, "removed cover should be null");

    console.log("preorder summary tests: all passed");
  } finally {
    for (const id of created.orderIds) {
      await prisma.order.deleteMany({ where: { id } });
    }
    for (const id of created.campaignIds) {
      await prisma.preOrderCampaign.deleteMany({ where: { id } });
    }
    for (const id of created.listingIds) {
      await prisma.listing.deleteMany({ where: { id, campaignId: null } });
    }
    await prisma.order.deleteMany({
      where: { buyerId: { in: [buyer2.id, otherSeller.id] } },
    });
    await prisma.user.deleteMany({
      where: { id: { in: [buyer2.id, otherSeller.id] } },
    });
    server.close();
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
