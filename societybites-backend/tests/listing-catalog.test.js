require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");
const campaignRoutes = require("../routes/preorderCampaigns");
const { canonicalCityKey } = require("../lib/launchCity");

const SEED_BUYER_PHONE = "+919845154070";
const SEED_SELLER_PHONE = "+919901844776";

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

function futureDates() {
  return {
    orderOpenAt: new Date(Date.now() - 60 * 1000),
    orderCutoffAt: new Date(Date.now() + 60 * 60 * 1000),
    fulfilmentAt: new Date(Date.now() + 2 * 60 * 60 * 1000),
  };
}

async function main() {
  const stamp = Date.now();
  const seller = await prisma.user.findUnique({ where: { phone: SEED_SELLER_PHONE } });
  const buyer = await prisma.user.findUnique({ where: { phone: SEED_BUYER_PHONE } });
  assert(seller && seller.societyId, "Seed seller with a society must exist");
  assert(buyer && buyer.societyId === seller.societyId, "Seed buyer must share the seller society");

  const sellerToken = signToken(seller);
  const buyerToken = signToken(buyer);
  const created = {
    listingIds: [],
    campaignIds: [],
    orderIds: [],
    userIds: [],
    societyIds: [],
    cityKeys: [],
  };

  const otherSeller = await prisma.user.create({
    data: {
      phone: `+91988${String(stamp).slice(-7)}`,
      name: "Other catalog seller",
      role: "seller",
      societyId: seller.societyId,
      upiId: "other@upi",
    },
  });
  created.userIds.push(otherSeller.id);
  const otherToken = signToken(otherSeller);

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  app.use("/preorder-campaigns", campaignRoutes);
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
    const regular = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: { name: `Catalog regular ${stamp}`, price: 40, foodType: "VEG" },
    });
    assert(regular.status === 201, `create regular failed: ${JSON.stringify(regular.json)}`);
    assert(regular.json.catalogType === "REGULAR", "new listing must default to REGULAR");
    created.listingIds.push(regular.json.id);

    const preorder = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: `Catalog preorder ${stamp}`,
        price: 90,
        foodType: "VEG",
        catalogType: "PREORDER",
      },
    });
    assert(preorder.status === 201, `create PREORDER failed: ${JSON.stringify(preorder.json)}`);
    assert(preorder.json.catalogType === "PREORDER", "seller can create PREORDER listing");
    created.listingIds.push(preorder.json.id);

    const toPreorder = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${regular.json.id}/catalog`,
      token: sellerToken,
      body: { catalogType: "PREORDER" },
    });
    assert(toPreorder.status === 200, `move to PREORDER failed: ${JSON.stringify(toPreorder.json)}`);
    assert(toPreorder.json.catalogType === "PREORDER", "REGULAR → PREORDER");
    assert(toPreorder.json.id === regular.json.id, "move must keep listing id");
    assert(toPreorder.json.price === 40, "move must keep price");

    const toRegular = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${regular.json.id}/catalog`,
      token: sellerToken,
      body: { catalogType: "REGULAR" },
    });
    assert(toRegular.status === 200, `move to REGULAR failed: ${JSON.stringify(toRegular.json)}`);
    assert(toRegular.json.catalogType === "REGULAR", "PREORDER → REGULAR");

    const buyerMove = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${regular.json.id}/catalog`,
      token: buyerToken,
      body: { catalogType: "PREORDER" },
    });
    assert(buyerMove.status === 403, `buyer catalog change must be 403, got ${buyerMove.status}`);

    const otherMove = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${regular.json.id}/catalog`,
      token: otherToken,
      body: { catalogType: "PREORDER" },
    });
    assert(otherMove.status === 403, `other seller catalog change must be 403, got ${otherMove.status}`);

    const invalid = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${regular.json.id}/catalog`,
      token: sellerToken,
      body: { catalogType: "BOTH" },
    });
    assert(invalid.status === 400, `invalid catalogType must be 400, got ${invalid.status}`);

    const invalidList = await jsonRequest(server, {
      method: "GET",
      path: "/listings?catalogType=BOTH",
      token: buyerToken,
    });
    assert(invalidList.status === 400, `invalid list catalogType must be 400, got ${invalidList.status}`);

    const market = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token: buyerToken,
    });
    assert(market.status === 200, `GET /listings failed: ${market.status}`);
    const marketIds = (market.json || []).map((item) => item.id);
    assert(marketIds.includes(regular.json.id), "REGULAR listing must appear in marketplace");
    assert(!marketIds.includes(preorder.json.id), "GET /listings must exclude PREORDER listings");

    const storefront = await jsonRequest(server, {
      method: "GET",
      path: `/listings?sellerId=${seller.id}`,
      token: buyerToken,
    });
    assert(storefront.status === 200, "storefront listings failed");
    const storefrontIds = (storefront.json || []).map((item) => item.id);
    assert(storefrontIds.includes(regular.json.id), "regular storefront should include REGULAR listing");
    assert(
      !storefrontIds.includes(preorder.json.id),
      "regular seller storefront must not expose PREORDER listings"
    );

    const buyerPreorderQuery = await jsonRequest(server, {
      method: "GET",
      path: `/listings?sellerId=${seller.id}&catalogType=PREORDER`,
      token: buyerToken,
    });
    assert(buyerPreorderQuery.status === 200, "non-owner PREORDER query should coerce to REGULAR");
    const coercedIds = (buyerPreorderQuery.json || []).map((item) => item.id);
    assert(!coercedIds.includes(preorder.json.id), "buyers must not receive PREORDER via catalogType query");

    const ownerPreorder = await jsonRequest(server, {
      method: "GET",
      path: `/listings?sellerId=${seller.id}&status=all&catalogType=PREORDER`,
      token: sellerToken,
    });
    assert(ownerPreorder.status === 200, "owner PREORDER catalog failed");
    const ownerIds = (ownerPreorder.json || []).map((item) => item.id);
    assert(ownerIds.includes(preorder.json.id), "seller must see own PREORDER catalog");

    const buyerGetPreorder = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${preorder.json.id}`,
      token: buyerToken,
    });
    assert(buyerGetPreorder.status === 404, "GET /listings/:id must not expose PREORDER marketplace listing");

    const ownerGetPreorder = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${preorder.json.id}`,
      token: sellerToken,
    });
    assert(ownerGetPreorder.status === 200, "owner can load PREORDER listing");
    assert(ownerGetPreorder.json.catalogType === "PREORDER", "owner GET keeps PREORDER");

    const campaign = await jsonRequest(server, {
      method: "POST",
      path: "/preorder-campaigns",
      token: sellerToken,
      body: {
        title: `Catalog campaign ${stamp}`,
        ...futureDates(),
        status: "open",
        products: [
          {
            listingId: preorder.json.id,
            name: preorder.json.name,
            price: 95,
            foodType: "VEG",
            inventoryMode: "demand",
          },
        ],
      },
    });
    assert(campaign.status === 201, `campaign create failed: ${JSON.stringify(campaign.json)}`);
    created.campaignIds.push(campaign.json.id);
    const campaignProduct = (campaign.json.products || [])[0];
    assert(campaignProduct, "campaign must include copied product");
    assert(campaignProduct.catalogType === "PREORDER", "campaign copy stays PREORDER");
    assert(campaignProduct.id !== preorder.json.id, "campaign product is a copy");
    created.listingIds.push(campaignProduct.id);
    const storedCopy = await prisma.listing.findUnique({
      where: { id: campaignProduct.id },
      select: { sourceListingId: true },
    });
    assert(
      storedCopy && storedCopy.sourceListingId === preorder.json.id,
      "campaign copy must store sourceListingId"
    );

    const campaignGet = await jsonRequest(server, {
      method: "GET",
      path: `/preorder-campaigns/${campaign.json.id}`,
      token: buyerToken,
    });
    assert(campaignGet.status === 200, "pre-order APIs must still expose campaign products");
    assert(
      (campaignGet.json.products || []).some((item) => item.id === campaignProduct.id),
      "PREORDER listing remains available through pre-order APIs"
    );

    const regularSourceCampaign = await jsonRequest(server, {
      method: "POST",
      path: `/preorder-campaigns/${campaign.json.id}/products`,
      token: sellerToken,
      body: {
        listingId: regular.json.id,
        name: regular.json.name,
        price: 40,
        foodType: "VEG",
        inventoryMode: "demand",
      },
    });
    assert(regularSourceCampaign.status === 400, "campaign products must not come from REGULAR catalog");

    const preorderOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: preorder.json.id, quantity: 1 }],
      },
    });
    assert(preorderOrder.status === 400, "POST /orders must reject PREORDER catalog listing");
    assert(
      String(preorderOrder.json && preorderOrder.json.error).includes("pre-orders only"),
      `unexpected PREORDER order error: ${JSON.stringify(preorderOrder.json)}`
    );

    const regularOrder = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        items: [{ listingId: regular.json.id, quantity: 1 }],
      },
    });
    assert(regularOrder.status === 201, `regular order failed: ${JSON.stringify(regularOrder.json)}`);
    created.orderIds.push(regularOrder.json.id);

    await prisma.review.create({
      data: {
        orderId: regularOrder.json.id,
        listingId: regular.json.id,
        reviewerId: buyer.id,
        rating: 5,
        comment: "catalog move should keep this",
      },
    });

    const afterReview = await jsonRequest(server, {
      method: "GET",
      path: `/listings/${regular.json.id}`,
      token: buyerToken,
    });
    assert(afterReview.status === 200, "buyer can still load REGULAR listing");
    assert(afterReview.json.reviewCount === 1, "review must be attached before catalog move");
    assert(afterReview.json.avgRating === 5, "rating before move");

    const orderSnapshot = await prisma.order.findUnique({
      where: { id: regularOrder.json.id },
      include: { items: true },
    });
    const itemSnapshot = {
      listingId: orderSnapshot.items[0].listingId,
      price: orderSnapshot.items[0].price,
      quantity: orderSnapshot.items[0].quantity,
      total: orderSnapshot.total,
      status: orderSnapshot.status,
    };

    const hideFromMarket = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${regular.json.id}/catalog`,
      token: sellerToken,
      body: { catalogType: "PREORDER" },
    });
    assert(hideFromMarket.status === 200, "move after historical order should succeed");
    assert(hideFromMarket.json.id === regular.json.id, "listing id preserved");
    assert(hideFromMarket.json.reviewCount === 1, "moving catalog must not reset reviews");
    assert(hideFromMarket.json.avgRating === 5, "moving catalog must not reset ratings");

    const marketAfterMove = await jsonRequest(server, {
      method: "GET",
      path: "/listings",
      token: buyerToken,
    });
    const marketAfterIds = (marketAfterMove.json || []).map((item) => item.id);
    assert(!marketAfterIds.includes(regular.json.id), "moved PREORDER listing leaves marketplace");

    const orderAfterMove = await prisma.order.findUnique({
      where: { id: regularOrder.json.id },
      include: { items: true },
    });
    assert(orderAfterMove.items[0].listingId === itemSnapshot.listingId, "historical listingId unchanged");
    assert(orderAfterMove.items[0].price === itemSnapshot.price, "historical price unchanged");
    assert(orderAfterMove.items[0].quantity === itemSnapshot.quantity, "historical quantity unchanged");
    assert(orderAfterMove.total === itemSnapshot.total, "historical total unchanged");
    assert(orderAfterMove.status === itemSnapshot.status, "historical status unchanged");

    const priceEdit = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${regular.json.id}`,
      token: sellerToken,
      body: { price: 55 },
    });
    assert(priceEdit.status === 200, `price edit failed: ${JSON.stringify(priceEdit.json)}`);
    assert(priceEdit.json.catalogType === "PREORDER", "editing must not reset catalogType");
    assert(priceEdit.json.price === 55, "price should update");

    const blockedMove = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${preorder.json.id}/catalog`,
      token: sellerToken,
      body: { catalogType: "REGULAR" },
    });
    assert(blockedMove.status === 400, "active campaign item cannot be moved");
    assert(
      String(blockedMove.json && blockedMove.json.error).includes("active pre-order campaign"),
      `unexpected active-campaign error: ${JSON.stringify(blockedMove.json)}`
    );

    const blockedDelete = await jsonRequest(server, {
      method: "DELETE",
      path: `/listings/${preorder.json.id}`,
      token: sellerToken,
    });
    assert(blockedDelete.status === 400, "active campaign item cannot be deleted");

    const sameNameTwin = await jsonRequest(server, {
      method: "POST",
      path: "/listings",
      token: sellerToken,
      body: {
        name: preorder.json.name,
        price: 45,
        foodType: "VEG",
        catalogType: "REGULAR",
      },
    });
    assert(sameNameTwin.status === 201, `same-name twin create failed: ${JSON.stringify(sameNameTwin.json)}`);
    created.listingIds.push(sameNameTwin.json.id);
    assert(sameNameTwin.json.name === preorder.json.name, "twin shares the campaign listing name");
    assert(sameNameTwin.json.id !== preorder.json.id, "twin is a different listing");

    const twinMove = await jsonRequest(server, {
      method: "PATCH",
      path: `/listings/${sameNameTwin.json.id}/catalog`,
      token: sellerToken,
      body: { catalogType: "PREORDER" },
    });
    assert(
      twinMove.status === 200,
      `same-name listing not in the campaign must be movable: ${JSON.stringify(twinMove.json)}`
    );
    assert(twinMove.json.catalogType === "PREORDER", "twin move should succeed");

    const twinDelete = await jsonRequest(server, {
      method: "DELETE",
      path: `/listings/${sameNameTwin.json.id}`,
      token: sellerToken,
    });
    assert(
      twinDelete.status === 200,
      `same-name listing not in the campaign must be deletable: ${JSON.stringify(twinDelete.json)}`
    );

    const city = `CatalogVille ${stamp}`;
    const cityKey = canonicalCityKey(city);
    const buyerSociety = await prisma.society.create({
      data: {
        name: `Catalog buyer ${stamp}`,
        city,
        inviteCode: `CB${String(stamp).slice(-8)}`,
        latitude: 12.9716,
        longitude: 77.5946,
      },
    });
    created.societyIds.push(buyerSociety.id);
    const nearbySociety = await prisma.society.create({
      data: {
        name: `Catalog nearby ${stamp}`,
        city,
        inviteCode: `CN${String(stamp).slice(-8)}`,
        latitude: 12.9986,
        longitude: 77.5946,
      },
    });
    created.societyIds.push(nearbySociety.id);
    const nearbyBuyer = await prisma.user.create({
      data: {
        phone: `+91981${String(stamp).slice(-7)}`,
        name: "Nearby catalog buyer",
        role: "buyer",
        societyId: buyerSociety.id,
      },
    });
    created.userIds.push(nearbyBuyer.id);
    const nearbySeller = await prisma.user.create({
      data: {
        phone: `+91982${String(stamp).slice(-7)}`,
        name: "Nearby catalog seller",
        role: "seller",
        societyId: nearbySociety.id,
        sellingReachLevel: "NEARBY",
        upiId: "nearby@upi",
      },
    });
    created.userIds.push(nearbySeller.id);
    const visibleNearby = await prisma.listing.create({
      data: {
        sellerId: nearbySeller.id,
        societyId: nearbySociety.id,
        name: `Nearby regular ${stamp}`,
        price: 70,
        quantity: 2,
        status: "active",
        catalogType: "REGULAR",
        foodType: "VEG",
      },
    });
    created.listingIds.push(visibleNearby.id);
    const hiddenNearby = await prisma.listing.create({
      data: {
        sellerId: nearbySeller.id,
        societyId: nearbySociety.id,
        name: `Nearby preorder ${stamp}`,
        price: 70,
        quantity: 2,
        status: "active",
        catalogType: "PREORDER",
        foodType: "VEG",
      },
    });
    created.listingIds.push(hiddenNearby.id);
    await prisma.cityReachConfig.upsert({
      where: { cityKey },
      create: {
        cityKey,
        displayName: city,
        nearbyRadiusKm: 5,
        extendedRadiusKm: 10,
      },
      update: {
        nearbyRadiusKm: 5,
        extendedRadiusKm: 10,
      },
    });
    created.cityKeys.push(cityKey);

    const nearbyToken = signToken(nearbyBuyer);
    const nearbyList = await jsonRequest(server, {
      method: "GET",
      path: "/listings/nearby-sellers",
      token: nearbyToken,
    });
    assert(nearbyList.status === 200, `nearby discovery failed: ${JSON.stringify(nearbyList.json)}`);
    const nearbySellerCard = (nearbyList.json.sellers || []).find(
      (card) => card.seller && card.seller.id === nearbySeller.id
    );
    assert(nearbySellerCard, "nearby seller with a REGULAR listing should appear");
    const previewIds = (nearbySellerCard.listings || []).map((item) => item.id);
    assert(previewIds.includes(visibleNearby.id), "nearby cards should preview REGULAR listings");
    assert(!previewIds.includes(hiddenNearby.id), "nearby cards must not preview PREORDER listings");

    const nearbyStorefront = await jsonRequest(server, {
      method: "GET",
      path: `/listings/nearby-sellers/${nearbySeller.id}`,
      token: nearbyToken,
    });
    assert(
      nearbyStorefront.status === 200,
      `nearby storefront failed: ${JSON.stringify(nearbyStorefront.json)}`
    );
    const nearbyStorefrontIds = (nearbyStorefront.json.listings || []).map((item) => item.id);
    assert(nearbyStorefrontIds.includes(visibleNearby.id), "nearby storefront should include REGULAR listing");
    assert(
      !nearbyStorefrontIds.includes(hiddenNearby.id),
      "nearby discovery must not expose PREORDER listings"
    );

    console.log("listing-catalog.test.js passed");
  } finally {
    server.close();
    if (created.orderIds.length) {
      await prisma.review.deleteMany({ where: { orderId: { in: created.orderIds } } }).catch(() => {});
      await prisma.orderItem.deleteMany({ where: { orderId: { in: created.orderIds } } }).catch(() => {});
      await prisma.order.deleteMany({ where: { id: { in: created.orderIds } } }).catch(() => {});
    }
    if (created.campaignIds.length) {
      await prisma.preOrderCampaign.deleteMany({ where: { id: { in: created.campaignIds } } }).catch(() => {});
    }
    if (created.listingIds.length) {
      await prisma.orderItem.deleteMany({ where: { listingId: { in: created.listingIds } } }).catch(() => {});
      await prisma.review.deleteMany({ where: { listingId: { in: created.listingIds } } }).catch(() => {});
      await prisma.listing.deleteMany({ where: { id: { in: created.listingIds } } }).catch(() => {});
    }
    if (created.userIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: created.userIds } } }).catch(() => {});
    }
    if (created.societyIds.length) {
      await prisma.society.deleteMany({ where: { id: { in: created.societyIds } } }).catch(() => {});
    }
    if (created.cityKeys.length) {
      await prisma.cityReachConfig.deleteMany({ where: { cityKey: { in: created.cityKeys } } }).catch(() => {});
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
