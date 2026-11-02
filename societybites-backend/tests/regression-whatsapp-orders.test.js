require("dotenv").config();

const prisma = require("../lib/prisma");
const {
  assert,
  jsonRequest,
  orderApp,
  listen,
  closeServer,
  createOrder,
  signToken,
} = require("./helpers/httpHarness");
const {
  installMockGraphFetch,
  waitForCalls,
} = require("./helpers/mockGraphFetch");
const {
  withWhatsAppOrderNotifications,
} = require("../lib/whatsappSetting");
const { ORDER_TEMPLATE_NAME } = require("../lib/whatsappCloud");

function uniquePhone(lead2) {
  const rest = `${Date.now()}${Math.floor(Math.random() * 1000)}`.slice(-8);
  return `+91${lead2}${rest}`;
}

function graphBody(call) {
  return JSON.parse(call.options.body);
}

async function main() {
  const stamp = Date.now();
  const societyIds = [];
  const userIds = [];
  const listingIds = [];
  const orderIds = [];

  const prevTemplate = process.env.WHATSAPP_TEMPLATE_NAME;
  const prevEnabled = process.env.WHATSAPP_ENABLED;
  const prevToken = process.env.WHATSAPP_TOKEN;
  const prevPhoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;

  process.env.WHATSAPP_TOKEN = prevToken || "regression-whatsapp-token";
  process.env.WHATSAPP_PHONE_NUMBER_ID = prevPhoneId || "1356102247597493";
  process.env.WHATSAPP_ENABLED = "true";

  const graph = installMockGraphFetch();
  const society = await prisma.society.create({
    data: {
      name: `WA Reg ${stamp}`,
      city: "Phase5 Ville",
      inviteCode: `WA${Math.random().toString(36).slice(2, 10)}`,
      latitude: 12.9716,
      longitude: 77.5946,
    },
  });
  societyIds.push(society.id);

  const buyer = await prisma.user.create({
    data: {
      phone: uniquePhone("96"),
      name: "Neel",
      role: "buyer",
      societyId: society.id,
    },
  });
  userIds.push(buyer.id);

  const seller = await prisma.user.create({
    data: {
      phone: uniquePhone("95"),
      name: "Kavya",
      role: "seller",
      societyId: society.id,
      sellingReachLevel: "MY_SOCIETY",
      fulfilmentMode: "BUYER_PICKUP",
      paymentPreference: "UPI_AND_COD",
      upiId: "kavya@upi",
    },
  });
  userIds.push(seller.id);

  const listing = await prisma.listing.create({
    data: {
      sellerId: seller.id,
      societyId: society.id,
      name: "Poha",
      price: 120,
      quantity: 8,
      status: "active",
    },
  });
  listingIds.push(listing.id);

  const buyerToken = signToken(buyer);
  const server = await listen(orderApp());

  try {
    await withWhatsAppOrderNotifications(false, async () => {
      graph.calls.length = 0;
      const skipped = await createOrder(server, {
        token: buyerToken,
        listingId: listing.id,
        paymentMethod: "cash",
      });
      orderIds.push(skipped.id);
      await new Promise((resolve) => setTimeout(resolve, 200));
      assert(graph.calls.length === 0, "admin off must not call Graph");
    });

    process.env.WHATSAPP_TEMPLATE_NAME = ORDER_TEMPLATE_NAME;
    await withWhatsAppOrderNotifications(true, async () => {
      graph.calls.length = 0;
      const mapped = await jsonRequest(server, {
        method: "POST",
        path: "/orders",
        token: buyerToken,
        body: {
          paymentMethod: "cash",
          items: [{ listingId: listing.id, quantity: 2 }],
        },
      });
      assert(mapped.status === 201, `mapped create ${mapped.status}`);
      orderIds.push(mapped.json.id);
      await waitForCalls(graph.calls, 1, "new_order_notification send");
      const body = graphBody(graph.calls[0]);
      assert(body.template.name === ORDER_TEMPLATE_NAME, "order template name");
      const texts = body.template.components[0].parameters.map((row) => row.text);
      assert(texts.length === 5, "five body parameters");
      assert(texts[0] === "Kavya", "seller name from order");
      assert(texts[1] === mapped.json.orderNumber, "order number from order");
      assert(texts[2] === "Neel", "customer name from order");
      assert(texts[3] === "2 x Poha", "item summary from order");
      assert(texts[4] === String(mapped.json.total), "amount from order total");
      assert(!JSON.stringify(body).includes("₹"), "amount has no rupee symbol");
      assert(!String(graph.calls[0].options.headers.Authorization || "").includes("undefined"));
    });

    delete process.env.WHATSAPP_TEMPLATE_NAME;
    await withWhatsAppOrderNotifications(true, async () => {
      graph.calls.length = 0;
      const hello = await createOrder(server, {
        token: buyerToken,
        listingId: listing.id,
        paymentMethod: "cash",
      });
      orderIds.push(hello.id);
      await waitForCalls(graph.calls, 1, "hello_world send");
      const body = graphBody(graph.calls[0]);
      assert(body.template.name === "hello_world", "default template");
      assert(body.template.components === undefined, "hello_world has no parameters");
    });

    graph.restore();
    const failingGraph = installMockGraphFetch({
      ok: false,
      status: 401,
      body: { error: { message: "Authentication Error" } },
    });
    process.env.WHATSAPP_TEMPLATE_NAME = ORDER_TEMPLATE_NAME;
    await withWhatsAppOrderNotifications(true, async () => {
      const stillCreated = await createOrder(server, {
        token: buyerToken,
        listingId: listing.id,
        paymentMethod: "cash",
      });
      orderIds.push(stillCreated.id);
      assert(stillCreated.id, "Graph failure must not block order create");
      await waitForCalls(failingGraph.calls, 1, "failed Graph still attempted");
    });
    failingGraph.restore();

    console.log("regression-whatsapp-orders.test.js passed");
  } finally {
    graph.restore();
    if (prevTemplate === undefined) delete process.env.WHATSAPP_TEMPLATE_NAME;
    else process.env.WHATSAPP_TEMPLATE_NAME = prevTemplate;
    if (prevEnabled === undefined) delete process.env.WHATSAPP_ENABLED;
    else process.env.WHATSAPP_ENABLED = prevEnabled;
    if (prevToken === undefined) delete process.env.WHATSAPP_TOKEN;
    else process.env.WHATSAPP_TOKEN = prevToken;
    if (prevPhoneId === undefined) delete process.env.WHATSAPP_PHONE_NUMBER_ID;
    else process.env.WHATSAPP_PHONE_NUMBER_ID = prevPhoneId;

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
      await prisma.refreshToken.deleteMany({ where: { userId: { in: userIds } } }).catch(() => {});
      await prisma.deviceToken.deleteMany({ where: { userId: { in: userIds } } }).catch(() => {});
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
