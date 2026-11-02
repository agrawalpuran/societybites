require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const listingRoutes = require("../routes/listings");
const {
  listingMatchesPurchase,
  listingIdentityKeys,
  variantIdentityKey,
  attachPurchasedBefore,
  purchaseWindowStart,
} = require("../lib/buyerPurchaseHistory");
const { serializeListing } = require("../utils/listingSerializer");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function daysAgo(days) {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000);
}

function uniquePhone(lead) {
  const rest = `${Date.now()}${Math.floor(Math.random() * 1000)}`.slice(-8);
  return `+91${lead}${rest}`;
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
    req.end();
  });
}

async function main() {
  assert(
    serializeListing({ id: "x", seller: { id: "s" } }).purchasedBefore === false,
    "missing purchasedBefore stays false"
  );

  const purchased = new Set(["id:paneer-a", "v:seller-a:group-1:250 g"]);
  assert(
    listingMatchesPurchase(
      { id: "paneer-a", sellerId: "seller-a" },
      purchased
    ),
    "same listing id matches"
  );
  assert(
    !listingMatchesPurchase(
      { id: "other", sellerId: "seller-b" },
      purchased
    ),
    "different listing does not match"
  );
  assert(
    !listingMatchesPurchase(
      {
        id: "copy-from-b",
        sellerId: "seller-b",
        variantGroupId: "group-1",
        variantLabel: "250 g",
      },
      purchased
    ),
    "same size from another seller does not match"
  );
  assert(
    listingMatchesPurchase(
      {
        id: "new-250",
        sellerId: "seller-a",
        variantGroupId: "group-1",
        variantLabel: "250 g",
      },
      purchased
    ),
    "same seller + variant group + size matches"
  );
  assert(
    !listingMatchesPurchase(
      {
        id: "new-500",
        sellerId: "seller-a",
        variantGroupId: "group-1",
        variantLabel: "500 g",
      },
      purchased
    ),
    "different size in the same group does not match"
  );
  assert(
    listingIdentityKeys({
      id: "camp",
      sellerId: "seller-a",
      sourceListingId: "paneer-a",
    }).has("id:paneer-a"),
    "campaign copy also keys the source listing"
  );
  assert(
    variantIdentityKey("s", "g", "250 g") === "v:s:g:250 g",
    "variant key format"
  );

  const stamp = Date.now();
  const society = await prisma.society.findFirst({ where: { status: "active" } });
  assert(society, "seed society required");

  const ids = { users: [], listings: [], orders: [] };

  const buyer = await prisma.user.create({
    data: {
      phone: uniquePhone("91"),
      name: "Tried Buyer",
      role: "buyer",
      societyId: society.id,
    },
  });
  ids.users.push(buyer.id);
  const otherBuyer = await prisma.user.create({
    data: {
      phone: uniquePhone("92"),
      name: "Other Buyer",
      role: "buyer",
      societyId: society.id,
    },
  });
  ids.users.push(otherBuyer.id);
  const sellerA = await prisma.user.create({
    data: {
      phone: uniquePhone("93"),
      name: "Tried Seller A",
      role: "seller",
      societyId: society.id,
    },
  });
  ids.users.push(sellerA.id);
  const sellerB = await prisma.user.create({
    data: {
      phone: uniquePhone("94"),
      name: "Tried Seller B",
      role: "seller",
      societyId: society.id,
    },
  });
  ids.users.push(sellerB.id);

  async function makeListing(sellerId, name, extra = {}) {
    const listing = await prisma.listing.create({
      data: {
        sellerId,
        societyId: society.id,
        name: `${name} ${stamp}`,
        price: 80,
        quantity: 20,
        status: "active",
        ...extra,
      },
    });
    ids.listings.push(listing.id);
    return listing;
  }

  async function makeOrder({
    buyerId,
    listingId,
    status,
    quantity = 1,
    completedAt = null,
    pickedUpAt = null,
  }) {
    const order = await prisma.order.create({
      data: {
        orderNumber: `TR${stamp}${Math.floor(Math.random() * 9000 + 1000)}`,
        buyerId,
        societyId: society.id,
        status,
        paymentMethod: "cash",
        subtotal: 80 * quantity,
        total: 80 * quantity,
        completedAt,
        pickedUpAt,
        items: {
          create: {
            listingId,
            quantity,
            unitPrice: 80,
          },
        },
      },
    });
    ids.orders.push(order.id);
    return order;
  }

  const puff = await makeListing(sellerA.id, "Paneer puff");
  const puffB = await makeListing(sellerB.id, "Paneer puff");
  const khakra = await makeListing(sellerA.id, "Khakra");
  const size250 = await makeListing(sellerA.id, "Paneer", {
    variantGroupId: `grp-${stamp}`,
    variantLabel: "250 g",
  });
  const size500 = await makeListing(sellerA.id, "Paneer", {
    variantGroupId: `grp-${stamp}`,
    variantLabel: "500 g",
  });
  const pendingListing = await makeListing(sellerA.id, "Pending dish");
  const acceptedListing = await makeListing(sellerA.id, "Accepted dish");
  const cancelledListing = await makeListing(sellerA.id, "Cancelled dish");
  const oldListing = await makeListing(sellerA.id, "Old dish");
  const revivedListing = await makeListing(sellerA.id, "Revived dish");

  await makeOrder({
    buyerId: buyer.id,
    listingId: puff.id,
    status: "completed",
    quantity: 1,
    completedAt: daysAgo(10),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: puff.id,
    status: "completed",
    quantity: 5,
    completedAt: daysAgo(20),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: size250.id,
    status: "completed",
    quantity: 1,
    completedAt: daysAgo(40),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: pendingListing.id,
    status: "pending",
    completedAt: daysAgo(2),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: acceptedListing.id,
    status: "accepted",
    completedAt: daysAgo(2),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: cancelledListing.id,
    status: "cancelled",
    completedAt: daysAgo(2),
  });
  const rejectedListing = await makeListing(sellerA.id, "Rejected dish");
  await makeOrder({
    buyerId: buyer.id,
    listingId: rejectedListing.id,
    status: "rejected",
    completedAt: daysAgo(2),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: oldListing.id,
    status: "completed",
    completedAt: daysAgo(400),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: revivedListing.id,
    status: "completed",
    completedAt: daysAgo(400),
  });
  await makeOrder({
    buyerId: buyer.id,
    listingId: revivedListing.id,
    status: "completed",
    completedAt: daysAgo(90),
  });
  await makeOrder({
    buyerId: otherBuyer.id,
    listingId: khakra.id,
    status: "completed",
    completedAt: daysAgo(5),
  });

  const elevenMonths = await makeListing(sellerA.id, "Eleven months");
  await makeOrder({
    buyerId: buyer.id,
    listingId: elevenMonths.id,
    status: "completed",
    completedAt: daysAgo(330),
  });

  const rows = [
    puff,
    puffB,
    khakra,
    size250,
    size500,
    pendingListing,
    acceptedListing,
    cancelledListing,
    rejectedListing,
    oldListing,
    revivedListing,
    elevenMonths,
  ];
  await attachPurchasedBefore(prisma, rows, buyer.id);

  assert(puff.purchasedBefore === true, "one completed unit within 12 months");
  assert(puffB.purchasedBefore === false, "same name other seller is not TRIED");
  assert(khakra.purchasedBefore === false, "other product same seller is not TRIED");
  assert(size250.purchasedBefore === true, "purchased size is TRIED");
  assert(size500.purchasedBefore === false, "sibling size is not TRIED");
  assert(pendingListing.purchasedBefore === false, "pending is not TRIED");
  assert(acceptedListing.purchasedBefore === false, "accepted is not TRIED");
  assert(cancelledListing.purchasedBefore === false, "cancelled is not TRIED");
  assert(rejectedListing.purchasedBefore === false, "rejected is not TRIED");
  assert(oldListing.purchasedBefore === false, "13+ months only is not TRIED");
  assert(revivedListing.purchasedBefore === true, "old plus recent purchase is TRIED");
  assert(elevenMonths.purchasedBefore === true, "11 months ago is TRIED");

  const recreated = await makeListing(sellerA.id, "Paneer recreated", {
    variantGroupId: `grp-${stamp}`,
    variantLabel: "250 g",
  });
  await attachPurchasedBefore(prisma, [recreated], buyer.id);
  assert(
    recreated.purchasedBefore === true,
    "recreated listing with same seller variant identity is TRIED"
  );

  await attachPurchasedBefore(prisma, [khakra], otherBuyer.id);
  assert(khakra.purchasedBefore === true, "indicator is buyer-specific");

  await attachPurchasedBefore(prisma, [puff], null);
  assert(puff.purchasedBefore === false, "guest / missing viewer is not TRIED");

  const since = purchaseWindowStart();
  assert(since instanceof Date && since.getTime() < Date.now(), "window start is in the past");

  const app = express();
  app.use(express.json());
  app.use("/listings", listingRoutes);
  const server = await new Promise((resolve) => {
    const s = http.createServer(app);
    s.listen(0, "127.0.0.1", () => resolve(s));
  });

  try {
    const buyerToken = signToken(buyer);
    const otherToken = signToken(otherBuyer);
    const path = `/listings/${puff.id}`;
    const asBuyer = await jsonRequest(server, {
      method: "GET",
      path,
      token: buyerToken,
    });
    assert(asBuyer.status === 200, `buyer listing GET ${asBuyer.status}`);
    assert(asBuyer.json.purchasedBefore === true, "GET listing purchasedBefore true");
    assert(asBuyer.json.price === 80, "price unchanged");

    const asOther = await jsonRequest(server, {
      method: "GET",
      path,
      token: otherToken,
    });
    assert(asOther.status === 200, "other buyer can load listing");
    assert(asOther.json.purchasedBefore === false, "other buyer does not inherit TRIED");

    const search = await jsonRequest(server, {
      method: "GET",
      path: `/listings?societyId=${encodeURIComponent(society.id)}&status=discoverable&search=Paneer`,
      token: buyerToken,
    });
    assert(search.status === 200, "search still works");
    const rowsJson = Array.isArray(search.json) ? search.json : [];
    const found = rowsJson.find((row) => row.id === puff.id);
    if (found) {
      assert(found.purchasedBefore === true, "search result keeps TRIED");
    }
  } finally {
    server.close();
  }

  await prisma.orderItem.deleteMany({ where: { orderId: { in: ids.orders } } });
  await prisma.order.deleteMany({ where: { id: { in: ids.orders } } });
  await prisma.listing.deleteMany({ where: { id: { in: ids.listings } } });
  await prisma.user.deleteMany({ where: { id: { in: ids.users } } });
  await prisma.$disconnect();
  console.log("buyer-purchase-history.test.js passed");
}

main().catch(async (err) => {
  console.error(err);
  try {
    await prisma.$disconnect();
  } catch (_) {}
  process.exit(1);
});
