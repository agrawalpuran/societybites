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

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");
  const userCountBefore = await prisma.user.count();

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/preorder-campaigns", campaignRoutes);
  app.use("/orders", orderRoutes);
  app.use((err, _req, res, _next) => {
    const statusCode = err.statusCode || 500;
    res.status(statusCode).json({ error: statusCode === 500 ? "Internal server error" : err.message });
  });

  const server = await new Promise((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });

  const created = { campaignIds: [], orderIds: [], listingIds: [] };

  const leftover = await prisma.preOrderCampaign.findMany({
    where: { title: { startsWith: "Test Friday Specials" } },
    select: { id: true },
  });
  if (leftover.length) {
    await prisma.order.deleteMany({
      where: { campaignId: { in: leftover.map((c) => c.id) } },
    });
    await prisma.preOrderCampaign.deleteMany({
      where: { id: { in: leftover.map((c) => c.id) } },
    });
  }

  try {
    const dates = futureDates();
    const createdCampaign = await jsonRequest(server, {
      method: "POST",
      path: "/preorder-campaigns",
      token: sellerToken,
      body: {
        title: `Test Friday Specials ${Date.now()}`,
        orderOpenAt: dates.orderOpenAt.toISOString(),
        orderCutoffAt: dates.orderCutoffAt.toISOString(),
        fulfilmentAt: dates.fulfilmentAt.toISOString(),
        status: "open",
        offeredFulfilmentMethods: ["pickup", "seller_delivery"],
        defaultDeliveryCharge: 40,
        products: [
          { name: "Samosa", price: 20, inventoryMode: "demand" },
          { name: "Kachori", price: 25, inventoryMode: "demand" },
          { name: "Dhokla", price: 30, inventoryMode: "limited", quantity: 2 },
        ],
      },
    });
    assert(createdCampaign.status === 201, `campaign create failed: ${createdCampaign.status}`);
    const campaign = createdCampaign.json;
    created.campaignIds.push(campaign.id);
    assert(campaign.coverImageUrl === null, "campaign cover should be nullable");
    const samosa = campaign.products.find((p) => p.name === "Samosa");
    const kachori = campaign.products.find((p) => p.name === "Kachori");
    const dhokla = campaign.products.find((p) => p.name === "Dhokla");
    assert(samosa && kachori && dhokla, "campaign products missing");
    created.listingIds.push(samosa.id, kachori.id, dhokla.id);

    const campaignDetail = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.id}`,
      token: buyerToken,
    });
    assert(campaignDetail.status === 200, "campaign detail failed");
    assert(
      campaignDetail.json.coverImageUrl === null,
      "campaign detail must include a null cover image"
    );

    const catalog = await jsonRequest(server, {
      method: "GET",
      path: `/listings?societyId=${encodeURIComponent(seller.societyId)}`,
      token: buyerToken,
    });
    assert(catalog.status === 200, "listings GET failed");
    assert(
      !catalog.json.some((l) => l.id === samosa.id),
      "campaign products must not appear in regular listing catalog"
    );

    const demandQtyBefore = (await prisma.listing.findUnique({ where: { id: samosa.id } })).quantity;
    const demandOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "seller_delivery",
        paymentMethod: "upi",
        items: [
          { listingId: samosa.id, quantity: 3 },
          { listingId: kachori.id, quantity: 1 },
        ],
      },
    });
    assert(demandOrder.status === 201, `demand order failed: ${JSON.stringify(demandOrder.json)}`);
    created.orderIds.push(demandOrder.json.id);
    assert(demandOrder.json.type === "pre_order", "type should be pre_order");
    assert(demandOrder.json.items.length === 2, "multi-product order");
    assert(demandOrder.json.deliveryCharge === 40, "one delivery charge for seller_delivery");
    assert(
      demandOrder.json.total === demandOrder.json.subtotal + demandOrder.json.communityFee + 40,
      "total includes one delivery charge"
    );
    const demandQtyAfter = (await prisma.listing.findUnique({ where: { id: samosa.id } })).quantity;
    assert(demandQtyAfter === demandQtyBefore, "demand-based must not decrement listing.quantity");

    const pickupOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "pickup",
        paymentMethod: "cash",
        items: [{ listingId: samosa.id, quantity: 1 }],
      },
    });
    assert(pickupOrder.status === 201, "pickup order failed");
    created.orderIds.push(pickupOrder.json.id);
    assert(pickupOrder.json.deliveryCharge === 0, "pickup deliveryCharge must be 0");

    const limitedFirst = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "pickup",
        items: [{ listingId: dhokla.id, quantity: 2 }],
      },
    });
    assert(limitedFirst.status === 201, "limited order failed");
    created.orderIds.push(limitedFirst.json.id);
    const dhoklaAfter = await prisma.listing.findUnique({ where: { id: dhokla.id } });
    assert(dhoklaAfter.quantity === 0, "limited inventory must decrement atomically");

    const limitedOver = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "pickup",
        items: [{ listingId: dhokla.id, quantity: 1 }],
      },
    });
    assert(limitedOver.status === 409 || limitedOver.status === 400, "oversell limited product must be rejected");

    const regularListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: seller.societyId,
        name: `Regular regression ${Date.now()}`,
        price: 50,
        quantity: 5,
        status: "active",
      },
    });
    created.listingIds.push(regularListing.id);

    const mixed = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "pickup",
        items: [
          { listingId: samosa.id, quantity: 1 },
          { listingId: regularListing.id, quantity: 1 },
        ],
      },
    });
    assert(mixed.status === 400, "mixed regular/pre-order must be rejected");

    const regularOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: regularListing.id, quantity: 2 }],
      },
    });
    assert(regularOrder.status === 201, `regular order failed: ${JSON.stringify(regularOrder.json)}`);
    created.orderIds.push(regularOrder.json.id);
    const regularAfter = await prisma.listing.findUnique({ where: { id: regularListing.id } });
    assert(regularAfter.quantity === 3, "regular listing quantity must still decrement");
    assert((regularOrder.json.type || "regular") === "regular", "regular type default");
    assert((regularOrder.json.deliveryCharge || 0) === 0, "regular orders have no delivery charge");

    const cancelBefore = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${pickupOrder.json.id}/status`,
      token: buyerToken,
      body: { status: "cancelled" },
    });
    assert(cancelBefore.status === 200, "cancel before cutoff should succeed");

    await prisma.preOrderCampaign.update({
      where: { id: campaign.id },
      data: { orderCutoffAt: new Date(Date.now() - 1000) },
    });
    const cancelAfter = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${demandOrder.json.id}/status`,
      token: buyerToken,
      body: { status: "cancelled" },
    });
    assert(cancelAfter.status === 400, "cancel after cutoff must be rejected");

    const afterCutoffOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "pickup",
        items: [{ listingId: samosa.id, quantity: 1 }],
      },
    });
    assert(afterCutoffOrder.status === 400, "orders after cutoff must be rejected");

    const pricePatch = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}/products/${samosa.id}`,
      token: sellerToken,
      body: { price: 99 },
    });
    assert(pricePatch.status === 400, "price change after first order must be rejected");

    const userCountAfter = await prisma.user.count();
    assert(userCountAfter === userCountBefore, "tests must not create users");

    console.log("preorder tests: all passed");
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
    server.close();
    await prisma.$disconnect();
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
