require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const orderRoutes = require("../routes/orders");
const campaignRoutes = require("../routes/preorderCampaigns");
const listingRoutes = require("../routes/listings");

const BUYER_PHONE = "+919845154070";
const SELLER_PHONE = "+919901844776";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body }) {
  const address = server.address();
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : Buffer.from(JSON.stringify(body));
    const request = http.request(
      {
        hostname: "127.0.0.1",
        port: address.port,
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
      (response) => {
        let data = "";
        response.on("data", (chunk) => (data += chunk));
        response.on("end", () => {
          let json = null;
          try {
            json = data ? JSON.parse(data) : null;
          } catch (_) {}
          resolve({ status: response.statusCode, json });
        });
      }
    );
    request.on("error", reject);
    if (payload) request.write(payload);
    request.end();
  });
}

function dates() {
  return {
    orderOpenAt: new Date(Date.now() - 2 * 60 * 1000),
    orderCutoffAt: new Date(Date.now() + 90 * 60 * 1000),
    fulfilmentAt: new Date(Date.now() + 3 * 60 * 60 * 1000),
  };
}

async function main() {
  const buyer = await prisma.user.findUnique({ where: { phone: BUYER_PHONE } });
  const seller = await prisma.user.findUnique({ where: { phone: SELLER_PHONE } });
  assert(buyer && seller, "Seed buyer and seller must exist");

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);
  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/preorder-campaigns", campaignRoutes);
  app.use("/orders", orderRoutes);
  app.use((error, _request, response, _next) => {
    const status = error.statusCode || 500;
    response.status(status).json({
      error: status === 500 ? "Internal server error" : error.message,
    });
  });
  const server = await new Promise((resolve) => {
    const instance = app.listen(0, "127.0.0.1", () => resolve(instance));
  });

  const created = { campaignIds: [], orderIds: [] };
  try {
    const initialDates = dates();
    const createResponse = await jsonRequest(server, {
      method: "POST",
      path: "/preorder-campaigns",
      token: sellerToken,
      body: {
        title: `Test Campaign Editing ${Date.now()}`,
        description: "Initial description",
        fulfilmentNotes: "Initial pickup note",
        orderOpenAt: initialDates.orderOpenAt.toISOString(),
        orderCutoffAt: initialDates.orderCutoffAt.toISOString(),
        fulfilmentAt: initialDates.fulfilmentAt.toISOString(),
        status: "open",
        offeredFulfilmentMethods: ["pickup"],
        defaultDeliveryCharge: 0,
        products: [
          {
            name: "Samosa",
            price: 20,
            inventoryMode: "demand",
          },
        ],
      },
    });
    assert(createResponse.status === 201, "campaign creation failed");
    const campaign = createResponse.json;
    created.campaignIds.push(campaign.id);
    let product = campaign.products[0];
    assert(campaign.fulfilmentNotes === "Initial pickup note", "create fulfilment notes");

    const editedDates = dates();
    const fullEdit = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}`,
      token: sellerToken,
      body: {
        title: "Edited Friday Specials",
        description: "Edited description",
        coverImageUrl: "/uploads/edited-cover.jpg",
        fulfilmentNotes: "Meet at the clubhouse",
        orderOpenAt: editedDates.orderOpenAt.toISOString(),
        orderCutoffAt: editedDates.orderCutoffAt.toISOString(),
        fulfilmentAt: editedDates.fulfilmentAt.toISOString(),
        offeredFulfilmentMethods: ["pickup", "seller_delivery"],
        defaultDeliveryCharge: 55,
      },
    });
    assert(fullEdit.status === 200, `zero-order campaign edit failed: ${fullEdit.status}`);
    assert(fullEdit.json.title === "Edited Friday Specials", "title editable before orders");
    assert(fullEdit.json.description === "Edited description", "description editable");
    assert(fullEdit.json.coverImageUrl === "/uploads/edited-cover.jpg", "cover editable");
    assert(fullEdit.json.fulfilmentNotes === "Meet at the clubhouse", "notes editable");
    assert(fullEdit.json.defaultDeliveryCharge === 55, "delivery charge editable");
    assert(fullEdit.json.offeredFulfilmentMethods.length === 2, "methods editable");

    const invalidTimeline = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}`,
      token: sellerToken,
      body: { orderCutoffAt: editedDates.fulfilmentAt.toISOString() },
    });
    assert(invalidTimeline.status === 400, "invalid campaign timeline must be rejected");

    const limitedEdit = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}/products/${product.id}`,
      token: sellerToken,
      body: {
        name: "Masala Samosa",
        price: 25,
        inventoryMode: "limited",
        quantity: 12,
      },
    });
    assert(limitedEdit.status === 200, "product edit before orders failed");
    assert(limitedEdit.json.name === "Masala Samosa", "product identity editable");
    assert(limitedEdit.json.price === 25, "product price editable");
    assert(limitedEdit.json.inventoryMode === "limited", "inventory mode editable");
    assert(limitedEdit.json.quantity === 12, "limited quantity editable");
    product = limitedEdit.json;

    const demandEdit = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}/products/${product.id}`,
      token: sellerToken,
      body: { inventoryMode: "demand" },
    });
    assert(demandEdit.status === 200, "switching to demand inventory failed");
    assert(demandEdit.json.quantity === 0, "demand inventory quantity must reset to zero");
    product = demandEdit.json;

    const addedBeforeOrder = await jsonRequest(server, {
      method: "POST",
      path: `/preorder-campaigns/${campaign.id}/products`,
      token: sellerToken,
      body: {
        name: "Temporary Product",
        price: 10,
        inventoryMode: "limited",
        quantity: 3,
      },
    });
    assert(addedBeforeOrder.status === 201, "product add before orders failed");
    const removedBeforeOrder = await jsonRequest(server, {
      method: "DELETE",
      path: `/preorder-campaigns/${campaign.id}/products/${addedBeforeOrder.json.id}`,
      token: sellerToken,
    });
    assert(removedBeforeOrder.status === 204, "product remove before orders failed");

    const orderResponse = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        type: "pre_order",
        campaignId: campaign.id,
        fulfilmentMethod: "seller_delivery",
        paymentMethod: "upi",
        items: [{ listingId: product.id, quantity: 2 }],
      },
    });
    assert(orderResponse.status === 201, `pre-order failed: ${orderResponse.status}`);
    created.orderIds.push(orderResponse.json.id);

    const orderBeforeEdits = await prisma.order.findUnique({
      where: { id: orderResponse.json.id },
      include: { items: true },
    });
    const orderSnapshot = JSON.stringify(orderBeforeEdits);

    const lockedCampaignChanges = [
      { title: "Confusing new title" },
      { orderOpenAt: new Date(Date.now() - 60 * 1000).toISOString() },
      { orderCutoffAt: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString() },
      { fulfilmentAt: new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString() },
      { offeredFulfilmentMethods: ["pickup"] },
      { defaultDeliveryCharge: 99 },
    ];
    for (const body of lockedCampaignChanges) {
      const response = await jsonRequest(server, {
        method: "PATCH",
        path: `/preorder-campaigns/${campaign.id}`,
        token: sellerToken,
        body,
      });
      assert(response.status === 400, `committed campaign change was allowed: ${JSON.stringify(body)}`);
    }

    const lockedProductChanges = [
      { name: "Renamed product" },
      { price: 99 },
      { inventoryMode: "limited", quantity: 10 },
      { quantity: 10 },
    ];
    for (const body of lockedProductChanges) {
      const response = await jsonRequest(server, {
        method: "PATCH",
        path: `/preorder-campaigns/${campaign.id}/products/${product.id}`,
        token: sellerToken,
        body,
      });
      assert(response.status === 400, `committed product change was allowed: ${JSON.stringify(body)}`);
    }

    const removeCommitted = await jsonRequest(server, {
      method: "DELETE",
      path: `/preorder-campaigns/${campaign.id}/products/${product.id}`,
      token: sellerToken,
    });
    assert(removeCommitted.status === 400, "committed product removal must fail");

    const genericListingPatch = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${product.id}`,
      token: sellerToken,
      body: { name: "Bypass rename", quantity: 500 },
    });
    assert(genericListingPatch.status === 400, "generic listing PATCH must not bypass locks");

    const genericListingPause = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${product.id}/pause`,
      token: sellerToken,
      body: {},
    });
    assert(genericListingPause.status === 400, "generic listing pause must not bypass locks");

    const genericListingDelete = await jsonRequest(server, {
      method: "DELETE",
      path: `/listings/${product.id}`,
      token: sellerToken,
    });
    assert(genericListingDelete.status === 400, "generic listing delete must not bypass locks");

    const safeEdit = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}`,
      token: sellerToken,
      body: {
        description: "Safe updated description",
        coverImageUrl: "/uploads/safe-cover.webp",
        fulfilmentNotes: "Updated coordination note",
      },
    });
    assert(safeEdit.status === 200, "safe committed campaign edits failed");
    assert(safeEdit.json.description === "Safe updated description", "safe description update");
    assert(safeEdit.json.coverImageUrl === "/uploads/safe-cover.webp", "safe cover update");
    assert(safeEdit.json.fulfilmentNotes === "Updated coordination note", "safe notes update");

    const addedAfterOrder = await jsonRequest(server, {
      method: "POST",
      path: `/preorder-campaigns/${campaign.id}/products`,
      token: sellerToken,
      body: {
        name: "New After Orders",
        price: 30,
        inventoryMode: "limited",
        quantity: 5,
      },
    });
    assert(addedAfterOrder.status === 201, "adding a new product after orders must succeed");

    const closeResponse = await jsonRequest(server, {
      method: "PATCH",
      path: `/preorder-campaigns/${campaign.id}`,
      token: sellerToken,
      body: { status: "closed" },
    });
    assert(closeResponse.status === 200, "closing committed campaign failed");
    assert(closeResponse.json.status === "closed", "campaign should be closed");

    const orderAfterEdits = await prisma.order.findUnique({
      where: { id: orderResponse.json.id },
      include: { items: true },
    });
    assert(
      JSON.stringify(orderAfterEdits) === orderSnapshot,
      "campaign edits must never modify existing orders or order items"
    );

    console.log("preorder editing tests: all passed");
  } finally {
    await prisma.order.deleteMany({ where: { id: { in: created.orderIds } } });
    await prisma.preOrderCampaign.deleteMany({
      where: { id: { in: created.campaignIds } },
    });
    server.close();
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
