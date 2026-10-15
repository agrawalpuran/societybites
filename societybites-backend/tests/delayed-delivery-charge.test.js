require("dotenv").config();
const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const { getPlatformFee } = require("../lib/platformFee");
const listingRoutes = require("../routes/listings");
const orderRoutes = require("../routes/orders");
const paymentRoutes = require("../routes/payments");
const authRoutes = require("../routes/auth");

const CITY_KEY = "phase5ville";

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

async function createSociety(name, extras = {}) {
  return prisma.society.create({
    data: {
      name,
      city: extras.city || "Phase5 Ville",
      inviteCode: `DL${Math.random().toString(36).slice(2, 10)}`,
      latitude: extras.latitude === undefined ? 12.9716 : extras.latitude,
      longitude: extras.longitude === undefined ? 77.5946 : extras.longitude,
    },
  });
}

async function createSeller(societyId, extras = {}) {
  return prisma.user.create({
    data: {
      phone: `+9199${String(Date.now()).slice(-8)}${Math.floor(Math.random() * 9)}`,
      role: "seller",
      societyId,
      sellingReachLevel: extras.reach || "NEARBY",
      fulfilmentMode: extras.fulfilmentMode || "BOTH",
      deliveryChargeNearby: extras.deliveryChargeNearby == null ? 30 : extras.deliveryChargeNearby,
      deliveryChargeInSociety: extras.deliveryChargeInSociety == null ? 0 : extras.deliveryChargeInSociety,
      paymentPreference: extras.paymentPreference || "UPI_AND_COD",
      upiId: "seller@upi",
    },
  });
}

async function main() {
  const stamp = Date.now();
  const listingIds = [];
  const userIds = [];
  const societyIds = [];
  const orderIds = [];
  let createdCityConfig = false;

  const buyerSociety = await createSociety(`DL Buyer ${stamp}`);
  societyIds.push(buyerSociety.id);
  const sellerSociety = await createSociety(`DL Seller ${stamp}`, {
    latitude: 12.9986,
    longitude: 77.5946,
  });
  societyIds.push(sellerSociety.id);

  const buyer = await prisma.user.create({
    data: {
      phone: `+9198${String(stamp).slice(-8)}`,
      role: "buyer",
      societyId: buyerSociety.id,
    },
  });
  userIds.push(buyer.id);

  const sellerBoth = await createSeller(sellerSociety.id);
  userIds.push(sellerBoth.id);
  const sellerUpiOutside = await createSeller(sellerSociety.id, {
    paymentPreference: "COD_IN_SOCIETY_UPI_OUTSIDE",
  });
  userIds.push(sellerUpiOutside.id);

  await prisma.cityReachConfig.upsert({
    where: { cityKey: CITY_KEY },
    update: { nearbyRadiusKm: 6, extendedRadiusKm: 12, displayName: "Phase5 Ville" },
    create: {
      cityKey: CITY_KEY,
      displayName: "Phase5 Ville",
      nearbyRadiusKm: 6,
      extendedRadiusKm: 12,
    },
  });
  createdCityConfig = true;

  const listing = await prisma.listing.create({
    data: {
      sellerId: sellerBoth.id,
      societyId: sellerSociety.id,
      name: `DL listing ${stamp}`,
      price: 100,
      quantity: 10,
      status: "active",
    },
  });
  listingIds.push(listing.id);

  const codBlockedListing = await prisma.listing.create({
    data: {
      sellerId: sellerUpiOutside.id,
      societyId: sellerSociety.id,
      name: `DL blocked ${stamp}`,
      price: 50,
      quantity: 5,
      status: "active",
    },
  });
  listingIds.push(codBlockedListing.id);

  const sameSocietySeller = await createSeller(buyerSociety.id, {
    reach: "MY_SOCIETY",
    fulfilmentMode: "SELLER_DELIVERY",
    deliveryChargeInSociety: 15,
  });
  userIds.push(sameSocietySeller.id);
  const sameListing = await prisma.listing.create({
    data: {
      sellerId: sameSocietySeller.id,
      societyId: buyerSociety.id,
      name: `DL same ${stamp}`,
      price: 60,
      quantity: 5,
      status: "active",
    },
  });
  listingIds.push(sameListing.id);

  const app = express();
  app.use(express.json());
  app.use("/auth", authRoutes);
  app.use("/listings", listingRoutes);
  app.use("/orders", orderRoutes);
  app.use("/payments", paymentRoutes);
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

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(sellerBoth);
  const otherBuyer = await prisma.user.create({
    data: {
      phone: `+9197${String(stamp).slice(-8)}`,
      role: "buyer",
      societyId: buyerSociety.id,
    },
  });
  userIds.push(otherBuyer.id);
  const otherBuyerToken = signToken(otherBuyer);

  const platformFee = await getPlatformFee();

  try {
    const crossCod = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        fulfilmentMethod: "seller_delivery",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(crossCod.status === 201, `cross COD create: ${JSON.stringify(crossCod.json)}`);
    orderIds.push(crossCod.json.id);
    assert(crossCod.json.deliveryCharge === 0, "initial delivery charge 0");
    assert(crossCod.json.deliveryChargePending === true, "pending flag");
    const expectedInitial = 100 + platformFee;
    assert(crossCod.json.total === expectedInitial, "total excludes delivery");

    const readyMissing = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossCod.json.id}/status`,
      token: sellerToken,
      body: { status: "ready" },
    });
    assert(readyMissing.status === 400, "ready without charge rejected");

    if (crossCod.json.status === "pending") {
      const accepted = await jsonRequest(server, {
        method: "PATCH",
        path: `/orders/${crossCod.json.id}/status`,
        token: sellerToken,
        body: { status: "accepted" },
      });
      assert(accepted.status === 200, "seller accept");
    }

    const readyCharge = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossCod.json.id}/status`,
      token: sellerToken,
      body: { status: "ready", deliveryCharge: 45 },
    });
    assert(readyCharge.status === 200, `ready with charge: ${JSON.stringify(readyCharge.json)}`);
    assert(readyCharge.json.deliveryCharge === 45, "saved delivery charge");
    assert(readyCharge.json.deliveryChargePending === false, "no longer pending");
    assert(readyCharge.json.total === 100 + platformFee + 45, "total includes delivery");

    const duplicateReady = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossCod.json.id}/status`,
      token: sellerToken,
      body: { status: "ready", deliveryCharge: 99 },
    });
    assert(duplicateReady.status === 400, "cannot mark ready twice");

    const crossZero = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        fulfilmentMethod: "seller_delivery",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(crossZero.status === 201, "second cross order");
    orderIds.push(crossZero.json.id);

    const buyerTamper = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossZero.json.id}/status`,
      token: buyerToken,
      body: { status: "ready", deliveryCharge: 1 },
    });
    assert(buyerTamper.status === 403, "buyer cannot set delivery charge");

    if (crossZero.json.status === "pending") {
      await jsonRequest(server, {
        method: "PATCH",
        path: `/orders/${crossZero.json.id}/status`,
        token: sellerToken,
        body: { status: "accepted" },
      });
    }
    const readyZero = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossZero.json.id}/status`,
      token: sellerToken,
      body: { status: "ready", deliveryCharge: 0 },
    });
    assert(readyZero.status === 200, "zero delivery accepted");
    assert(readyZero.json.deliveryCharge === 0, "zero stored");
    assert(readyZero.json.total === 100 + platformFee, "total with free delivery");

    const cashConfirm = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${crossCod.json.id}/confirm-cash`,
      token: sellerToken,
    });
    assert(cashConfirm.status === 200, "confirm cash");
    assert(cashConfirm.json.total === 100 + platformFee + 45, "cash confirm total");

    const crossPickup = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        fulfilmentMethod: "pickup",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(crossPickup.status === 201, "pickup order");
    orderIds.push(crossPickup.json.id);
    assert(crossPickup.json.deliveryCharge === 0, "pickup charge 0");
    assert(!crossPickup.json.deliveryChargePending, "pickup not pending");

    const crossUpi = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "upi",
        fulfilmentMethod: "seller_delivery",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(crossUpi.status === 201, "UPI cross order");
    orderIds.push(crossUpi.json.id);
    assert(crossUpi.json.deliveryCharge === 0, "UPI defers delivery charge");
    assert(crossUpi.json.deliveryChargePending === true, "UPI pending until ready");
    assert(
      crossUpi.json.upiFoodCashDeliverySplit === true,
      "UPI outside delivery split flag"
    );
    const foodOnly =
      crossUpi.json.subtotal + crossUpi.json.communityFee;
    assert(
      crossUpi.json.upiPayableAmount === foodOnly,
      "UPI payable is food-only at create"
    );

    if (crossUpi.json.status === "pending") {
      const upiAccept = await jsonRequest(server, {
        method: "PATCH",
        path: `/orders/${crossUpi.json.id}/status`,
        token: sellerToken,
        body: { status: "accepted" },
      });
      assert(upiAccept.status === 200, "accept UPI cross order");
    }
    const markPaid = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${crossUpi.json.id}/mark-paid`,
      token: buyerToken,
      body: {},
    });
    assert(markPaid.status === 200, "buyer mark paid");
    const confirmUpi = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${crossUpi.json.id}/confirm`,
      token: sellerToken,
      body: {},
    });
    assert(confirmUpi.status === 200, "seller confirm UPI food");
    const readyUpi = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossUpi.json.id}/status`,
      token: sellerToken,
      body: { status: "ready", deliveryCharge: 25, deliveryCollectBy: "seller" },
    });
    assert(readyUpi.status === 200, "UPI ready with delivery charge");
    assert(readyUpi.json.deliveryCollectBy === "seller", "collect by seller");
    assert(
      readyUpi.json.total === 100 + platformFee + 25,
      "UPI total includes delivery after ready"
    );
    const completeBlocked = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossUpi.json.id}/status`,
      token: sellerToken,
      body: { status: "completed" },
    });
    assert(completeBlocked.status === 400, "complete blocked before delivery cash");
    const deliveryCash = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${crossUpi.json.id}/confirm-delivery-cash`,
      token: sellerToken,
    });
    assert(deliveryCash.status === 200, "confirm delivery cash");
    assert(deliveryCash.json.deliveryCashConfirmed === true, "delivery cash flag");
    assert(deliveryCash.json.status === "completed", "auto-complete after delivery cash");

    const sameCod = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        fulfilmentMethod: "seller_delivery",
        items: [{ listingId: sameListing.id, quantity: 1 }],
      },
    });
    assert(sameCod.status === 201, "same-society COD");
    orderIds.push(sameCod.json.id);
    assert(sameCod.json.deliveryCharge === 15, "in-society charge snapshotted");
    assert(!sameCod.json.deliveryChargePending, "same-society not pending");
    const sameReady = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${sameCod.json.id}/status`,
      token: signToken(sameSocietySeller),
      body: { status: "ready" },
    });
    assert(sameReady.status === 200, "same-society ready without charge field");

    const blockedCod = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: buyerToken,
      body: {
        paymentMethod: "cash",
        fulfilmentMethod: "seller_delivery",
        items: [{ listingId: codBlockedListing.id, quantity: 1 }],
      },
    });
    assert(blockedCod.status === 400, "cross-society COD blocked by payment pref");

    const complete = await jsonRequest(server, {
      method: "PATCH",
      path: `/orders/${crossCod.json.id}/status`,
      token: sellerToken,
      body: { status: "completed" },
    });
    assert(complete.status === 200, "complete after cash paid");
  } finally {
    if (orderIds.length) {
      await prisma.couponRedemption.deleteMany({ where: { orderId: { in: orderIds } } }).catch(() => {});
      await prisma.orderItem.deleteMany({ where: { orderId: { in: orderIds } } }).catch(() => {});
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } }).catch(() => {});
    }
    await prisma.listing.deleteMany({ where: { id: { in: listingIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await prisma.society.deleteMany({ where: { id: { in: societyIds } } });
    void createdCityConfig;
    await new Promise((resolve) => server.close(resolve));
  }
}

main()
  .then(() => {
    console.log("delayed-delivery-charge tests passed");
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
