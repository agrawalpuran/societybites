require("dotenv").config();
const prisma = require("../lib/prisma");
const {
  assert,
  jsonRequest,
  orderApp,
  listen,
  closeServer,
  createOrder,
  patchStatus,
  signToken,
} = require("./helpers/httpHarness");

function uniquePhone(lead2) {
  const rest = `${Date.now()}${Math.floor(Math.random() * 1000)}`.slice(-8);
  return `+91${lead2}${rest}`;
}

async function main() {
  const stamp = Date.now();
  const societyIds = [];
  const userIds = [];
  const listingIds = [];
  const orderIds = [];

  const society = await prisma.society.create({
    data: {
      name: `Reg ${stamp}`,
      city: "Phase5 Ville",
      inviteCode: `RG${Math.random().toString(36).slice(2, 10)}`,
      latitude: 12.9716,
      longitude: 77.5946,
    },
  });
  societyIds.push(society.id);

  const otherSociety = await prisma.society.create({
    data: {
      name: `Reg Other ${stamp}`,
      city: "Other Ville",
      inviteCode: `RO${Math.random().toString(36).slice(2, 10)}`,
      latitude: 13.0827,
      longitude: 80.2707,
    },
  });
  societyIds.push(otherSociety.id);

  const buyer = await prisma.user.create({
    data: {
      phone: uniquePhone("98"),
      name: "Reg Buyer",
      role: "buyer",
      societyId: society.id,
    },
  });
  userIds.push(buyer.id);

  const outsider = await prisma.user.create({
    data: {
      phone: uniquePhone("97"),
      name: "Reg Outsider",
      role: "buyer",
      societyId: otherSociety.id,
    },
  });
  userIds.push(outsider.id);

  const seller = await prisma.user.create({
    data: {
      phone: uniquePhone("99"),
      name: "Reg Seller",
      role: "seller",
      societyId: society.id,
      sellingReachLevel: "MY_SOCIETY",
      fulfilmentMode: "BUYER_PICKUP",
      paymentPreference: "UPI_AND_COD",
      upiId: "reg@upi",
    },
  });
  userIds.push(seller.id);

  const listing = await prisma.listing.create({
    data: {
      sellerId: seller.id,
      societyId: society.id,
      name: `Reg Paneer ${stamp}`,
      price: 100,
      quantity: 5,
      status: "active",
    },
  });
  listingIds.push(listing.id);

  const buyerToken = signToken(buyer);
  const sellerToken = signToken(seller);
  const outsiderToken = signToken(outsider);

  const server = await listen(orderApp());

  try {
    const unauthCreate = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      body: {
        paymentMethod: "cash",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(
      unauthCreate.status === 401,
      `create without Authorization must be 401, got ${unauthCreate.status}`
    );
    assert(
      String(unauthCreate.json?.error || "").toLowerCase().includes("authorization"),
      "unauthenticated create should mention Authorization"
    );

    const unauthKitchen = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=active",
    });
    assert(
      unauthKitchen.status === 401,
      `seller bucket without auth must be 401, got ${unauthKitchen.status}`
    );

    const placed = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(placed.id);
    assert(placed.status === "accepted", "ready-now cash order must auto-accept");
    assert(placed.paymentStatus === "pending", "create must not mark cash paid");

    const stockAfterPlace = await prisma.listing.findUnique({
      where: { id: listing.id },
    });
    assert(stockAfterPlace.quantity === 4, "placing an order must decrement stock");

    const kitchen = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=active",
      token: sellerToken,
    });
    assert(kitchen.status === 200, "seller active bucket must load");
    const kitchenIds = (kitchen.json.orders || []).map((row) => row.id);
    assert(kitchenIds.includes(placed.id), "new order must appear in seller active bucket");

    const buyerList = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=buyer",
      token: buyerToken,
    });
    assert(buyerList.status === 200, "buyer orders list must load");
    const buyerListRows = Array.isArray(buyerList.json)
      ? buyerList.json
      : buyerList.json?.orders || [];
    assert(
      buyerListRows.some((row) => row.id === placed.id),
      "placed order must appear on buyer orders list"
    );

    const ready = await patchStatus(server, {
      token: sellerToken,
      orderId: placed.id,
      status: "ready",
    });
    assert(ready.status === 200, "accepted → ready");

    const cash = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${placed.id}/confirm-cash`,
      token: sellerToken,
    });
    assert(cash.status === 200, "confirm cash at ready");
    assert(cash.json.paymentStatus === "paid", "cash confirm sets paid");

    const completed = await patchStatus(server, {
      token: sellerToken,
      orderId: placed.id,
      status: "completed",
    });
    assert(completed.status === 200, "ready → completed");
    assert(completed.json.status === "completed", "complete stores completed");
    assert(completed.json.completedAt, "completedAt must be set");

    const buyerView = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${placed.id}`,
      token: buyerToken,
    });
    const sellerView = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${placed.id}`,
      token: sellerToken,
    });
    assert(buyerView.status === 200 && sellerView.status === 200, "both roles can GET the order");
    assert(
      buyerView.json.status === "completed" && sellerView.json.status === "completed",
      "buyer and seller must agree the order is completed"
    );
    assert(
      buyerView.json.paymentStatus === "paid" && sellerView.json.paymentStatus === "paid",
      "buyer and seller must agree payment is paid"
    );

    const secondComplete = await patchStatus(server, {
      token: sellerToken,
      orderId: placed.id,
      status: "completed",
    });
    assert(secondComplete.status === 400, "second complete must not rewrite a finished order");
    const stillDone = await prisma.order.findUnique({ where: { id: placed.id } });
    assert(stillDone.status === "completed", "failed second complete must leave status completed");

    const toReject = await createOrder(server, {
      token: buyerToken,
      listingId: listing.id,
      paymentMethod: "cash",
    });
    orderIds.push(toReject.id);
    const rejected = await jsonRequest(server, {
      method: "POST",
      path: `/orders/${toReject.id}/reject`,
      token: sellerToken,
      body: { reason: "Not enough time" },
    });
    assert(rejected.status === 200, "seller reject");
    assert(rejected.json.status === "rejected", "reject stores rejected");
    const stockAfterReject = await prisma.listing.findUnique({
      where: { id: listing.id },
    });
    assert(stockAfterReject.quantity === 4, "reject must restore listing stock");
    const buyerRejected = await jsonRequest(server, {
      method: "GET",
      path: `/orders/${toReject.id}`,
      token: buyerToken,
    });
    assert(buyerRejected.json.status === "rejected", "buyer sees rejected");
    assert(
      String(buyerRejected.json.rejectReason || "").includes("Not enough time"),
      "buyer sees reject reason"
    );

    const blocked = await jsonRequest(server, {
      method: "POST",
      path: "/orders",
      token: outsiderToken,
      body: {
        paymentMethod: "cash",
        items: [{ listingId: listing.id, quantity: 1 }],
      },
    });
    assert(
      blocked.status === 400 || blocked.status === 403,
      `MY_SOCIETY seller must not take another society's order, got ${blocked.status}`
    );

    const upiListing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: society.id,
        name: `Reg UPI ${stamp}`,
        price: 80,
        quantity: 2,
        status: "active",
      },
    });
    listingIds.push(upiListing.id);

    const upiOrder = await createOrder(server, {
      token: buyerToken,
      listingId: upiListing.id,
      paymentMethod: "upi",
    });
    orderIds.push(upiOrder.id);
    assert(
      upiOrder.paymentStatus === "pending",
      `UPI create must leave payment pending, got ${upiOrder.paymentStatus}`
    );

    let upiReadyId = upiOrder.id;
    if (upiOrder.status === "pending") {
      const acceptedUpi = await patchStatus(server, {
        token: sellerToken,
        orderId: upiOrder.id,
        status: "accepted",
      });
      assert(acceptedUpi.status === 200, "seller can accept UPI order");
      upiReadyId = acceptedUpi.json.id || upiOrder.id;
    }

    const markPaid = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${upiReadyId}/mark-paid`,
      token: buyerToken,
      body: { upiTransactionRef: `REG-UPI-${stamp}` },
    });
    assert(markPaid.status === 200, `buyer mark-paid must succeed, got ${markPaid.status}`);
    assert(
      markPaid.json.paymentStatus === "buyer_marked_paid",
      `buyer mark paid should set buyer_marked_paid, got ${markPaid.json.paymentStatus}`
    );

    const pastBucket = await jsonRequest(server, {
      method: "GET",
      path: "/orders?role=seller&scope=recent_past",
      token: sellerToken,
    });
    assert(pastBucket.status === 200, "seller recent_past bucket must load");
    assert(
      Array.isArray(pastBucket.json?.orders),
      "recent_past payload must include orders array"
    );
    // Freshly completed/rejected orders stay in Active grace, so they may not
    // appear in recent_past yet — only assert the bucket is readable.

    console.log("regression-order-journeys.test.js passed");
  } finally {
    if (orderIds.length) {
      await prisma.couponRedemption
        .deleteMany({ where: { orderId: { in: orderIds } } })
        .catch(() => {});
      await prisma.orderIdempotency
        .deleteMany({ where: { orderId: { in: orderIds } } })
        .catch(() => {});
      await prisma.order.deleteMany({ where: { id: { in: orderIds } } }).catch(() => {});
    }
    if (listingIds.length) {
      await prisma.listing.deleteMany({ where: { id: { in: listingIds } } }).catch(() => {});
    }
    if (userIds.length) {
      await prisma.user.deleteMany({ where: { id: { in: userIds } } }).catch(() => {});
    }
    if (societyIds.length) {
      await prisma.society.deleteMany({ where: { id: { in: societyIds } } }).catch(() => {});
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
