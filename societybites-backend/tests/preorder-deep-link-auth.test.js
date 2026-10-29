/**
 * Deep-link style access to GET /preorder-campaigns/:id
 * — unauthenticated must 401; joined buyer in reach must 200.
 */
require("dotenv").config();
const express = require("express");
const prisma = require("../lib/prisma");
const {
  assert,
  jsonRequest,
  listen,
  closeServer,
  signToken,
} = require("./helpers/httpHarness");
const campaignRoutes = require("../routes/preorderCampaigns");

function uniquePhone(lead2) {
  const rest = `${Date.now()}${Math.floor(Math.random() * 1000)}`.slice(-8);
  return `+91${lead2}${rest}`;
}

function futureDates() {
  const orderOpenAt = new Date(Date.now() - 60 * 1000);
  const orderCutoffAt = new Date(Date.now() + 60 * 60 * 1000);
  const fulfilmentAt = new Date(Date.now() + 2 * 60 * 60 * 1000);
  return { orderOpenAt, orderCutoffAt, fulfilmentAt };
}

function campaignApp() {
  const app = express();
  app.use(express.json());
  app.use("/preorder-campaigns", campaignRoutes);
  app.use((error, _req, res, _next) => {
    const statusCode = error.statusCode || 500;
    res
      .status(statusCode)
      .json({
        error: statusCode === 500 ? "Internal server error" : error.message,
      });
  });
  return app;
}

async function main() {
  const stamp = Date.now();
  const societyIds = [];
  const userIds = [];
  const campaignIds = [];
  const listingIds = [];

  const society = await prisma.society.create({
    data: {
      name: `DL Auth ${stamp}`,
      city: "DeepLink Ville",
      inviteCode: `DL${Math.random().toString(36).slice(2, 10)}`,
      latitude: 12.9716,
      longitude: 77.5946,
    },
  });
  societyIds.push(society.id);

  const otherSociety = await prisma.society.create({
    data: {
      name: `DL Other ${stamp}`,
      city: "Other Ville",
      inviteCode: `DO${Math.random().toString(36).slice(2, 10)}`,
      latitude: 13.0827,
      longitude: 80.2707,
    },
  });
  societyIds.push(otherSociety.id);

  const seller = await prisma.user.create({
    data: {
      phone: uniquePhone("91"),
      name: "DL Seller",
      role: "seller",
      societyId: society.id,
      sellingReachLevel: "MY_SOCIETY",
      fulfilmentMode: "BUYER_PICKUP",
      paymentPreference: "UPI_AND_COD",
      upiId: "dl@upi",
    },
  });
  userIds.push(seller.id);

  const buyer = await prisma.user.create({
    data: {
      phone: uniquePhone("92"),
      name: "DL Buyer",
      role: "buyer",
      societyId: society.id,
    },
  });
  userIds.push(buyer.id);

  const outsider = await prisma.user.create({
    data: {
      phone: uniquePhone("93"),
      name: "DL Outsider",
      role: "buyer",
      societyId: otherSociety.id,
    },
  });
  userIds.push(outsider.id);

  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);
  const outsiderToken = signToken(outsider);
  const dates = futureDates();

  const server = await listen(campaignApp());

  try {
    const created = await jsonRequest(server, {
      method: "POST",
      path: "/preorder-campaigns",
      token: sellerToken,
      body: {
        title: `Deep Link Campaign ${stamp}`,
        orderOpenAt: dates.orderOpenAt.toISOString(),
        orderCutoffAt: dates.orderCutoffAt.toISOString(),
        fulfilmentAt: dates.fulfilmentAt.toISOString(),
        status: "open",
        offeredFulfilmentMethods: ["pickup"],
        products: [
          {
            name: "Deep Link Samosa",
            price: 25,
            inventoryMode: "demand",
            foodType: "VEG",
          },
        ],
      },
    });
    assert(
      created.status === 201,
      `campaign create failed: ${created.status} ${JSON.stringify(created.json)}`
    );
    const campaignId = created.json.id;
    campaignIds.push(campaignId);
    const productIds = (created.json.products || []).map((p) => p.id);
    listingIds.push(...productIds);

    const unauth = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaignId}`,
    });
    assert(
      unauth.status === 401,
      `deep-link campaign GET without auth must be 401, got ${unauth.status}`
    );
    assert(
      String(unauth.json?.error || "")
        .toLowerCase()
        .includes("authorization"),
      "unauthenticated campaign GET should mention Authorization"
    );

    const authed = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaignId}`,
      token: buyerToken,
    });
    assert(
      authed.status === 200,
      `joined buyer must open campaign via deep-link id, got ${authed.status}`
    );
    assert(authed.json.id === campaignId, "response campaign id must match");
    assert(
      Array.isArray(authed.json.products) && authed.json.products.length >= 1,
      "authenticated detail must include products"
    );

    const blocked = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaignId}`,
      token: outsiderToken,
    });
    assert(
      blocked.status === 403 || blocked.status === 404,
      `other-society buyer must not view MY_SOCIETY campaign, got ${blocked.status}`
    );

    console.log("preorder-deep-link-auth.test.js passed");
  } finally {
    if (campaignIds.length) {
      await prisma.order
        .deleteMany({ where: { campaignId: { in: campaignIds } } })
        .catch(() => {});
      await prisma.listing
        .deleteMany({ where: { campaignId: { in: campaignIds } } })
        .catch(() => {});
      await prisma.preOrderCampaign
        .deleteMany({ where: { id: { in: campaignIds } } })
        .catch(() => {});
    }
    if (listingIds.length) {
      await prisma.listing
        .deleteMany({ where: { id: { in: listingIds } } })
        .catch(() => {});
    }
    if (userIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: userIds } } }).catch(() => {});
    }
    if (societyIds.length) {
      await prisma.society
        .deleteMany({ where: { id: { in: societyIds } } })
        .catch(() => {});
    }
    await closeServer(server);
    await prisma.$disconnect();
  }
}

main().catch(async (error) => {
  console.error(error.message || error);
  try {
    await prisma.$disconnect();
  } catch (_) {}
  process.exit(1);
});
