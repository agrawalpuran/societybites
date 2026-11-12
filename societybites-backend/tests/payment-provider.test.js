require("dotenv").config();

const http = require("http");
const express = require("express");
const prisma = require("../lib/prisma");
const { signToken } = require("../lib/jwt");
const paymentRoutes = require("../routes/payments");
const adminRoutes = require("../routes/admin");
const webhookRoutes = require("../routes/paymentWebhooks");
const { normalizePaymentProvider } = require("../lib/payments/providers");
const { sellerShareAmount } = require("../lib/payments/sellerShare");
const {
  signCashfreeBody,
  verifyCashfreeSignature,
} = require("../lib/payments/cashfreeSignature");
const {
  setPaymentFetch,
  resetPaymentFetch,
  PaymentHttpError,
  cashfreeReturnUrl,
} = require("../lib/payments/cashfreeClient");
const { PAYMENT_PROVIDER_KEY } = require("../lib/payments/paymentSetting");

const BUYER_PHONE = "+919810120001";
const SELLER_PHONE = "+919810120002";
const ADMIN_PHONE = "+919810120003";
const SECRET = "test-cashfree-secret";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function jsonRequest(server, { method, path, token, body, headers }) {
  const address = server.address();
  const payload = body === undefined ? null : Buffer.from(typeof body === "string" ? body : JSON.stringify(body));
  return new Promise((resolve, reject) => {
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
          ...(headers || {}),
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

function installFetch(state) {
  const calls = [];
  setPaymentFetch(async (url, options) => {
    const body = options.body ? JSON.parse(options.body) : null;
    calls.push({ url, method: options.method, body });
    if (url.endsWith("/pg/orders") && options.method === "POST") {
      return {
        order_id: body.order_id,
        order_amount: body.order_amount,
        payment_session_id: "session_test",
      };
    }
    if (url.endsWith("/pg/orders/sessions")) {
      const channel = body.payment_method.upi.channel;
      if (channel === "qrcode") {
        return {
          cf_payment_id: "qr1",
          data: { payload: { upi: "upi://pay?pa=order@cashfree&am=100" } },
        };
      }
      return {
        cf_payment_id: "link1",
        data: { url: "https://sandbox.cashfree.com/pg/upi/test-link" },
      };
    }
    if (url.includes("/easy-split/vendors/") && options.method === "GET") {
      return { status: state.vendorStatus, vendor_id: "vendor" };
    }
    if (url.endsWith("/pg/easy-split/vendors") && options.method === "POST") {
      return { status: "IN_BENE_CREATION", vendor_id: body.vendor_id };
    }
    if (url.includes("/easy-split/orders/") && url.endsWith("/split")) {
      if (state.splitError) throw state.splitError;
      return { status: "OK", message: "Order split created" };
    }
    throw new Error(`unexpected Cashfree call ${options.method} ${url}`);
  });
  return calls;
}

function splitCalls(calls) {
  return calls.filter((call) => call.url.endsWith("/split"));
}

function orderCreates(calls) {
  return calls.filter(
    (call) => call.method === "POST" && call.url.endsWith("/pg/orders")
  );
}

async function main() {
  assert(normalizePaymentProvider(undefined) === "direct_upi", "missing provider");
  assert(normalizePaymentProvider("payu") === "direct_upi", "unknown provider");
  assert(normalizePaymentProvider("cashfree") === "cashfree", "cashfree provider");
  assert(
    sellerShareAmount({ total: 100, communityFee: 10, gatewayAmount: 100 }) === 90,
    "seller share is total minus platform fee"
  );
  const signed = signCashfreeBody('{"ok":true}', "100", SECRET);
  assert(
    verifyCashfreeSignature({
      rawBody: '{"ok":true}',
      timestamp: "100",
      signature: signed,
      secret: SECRET,
    }),
    "valid signature"
  );
  assert(
    !verifyCashfreeSignature({
      rawBody: '{"ok":true}',
      timestamp: "100",
      signature: "nope",
      secret: SECRET,
    }),
    "bad signature"
  );
  assert(
    cashfreeReturnUrl({ origin: "http://localhost:49702", orderId: "abc" }) ===
      "http://localhost:49702/pay/return?order=abc&order_id={order_id}",
    "localhost return url"
  );
  assert(
    cashfreeReturnUrl({ origin: "https://www.societyeats.com", orderId: "abc" }) ===
      "https://www.societyeats.com/pay/return?order=abc&order_id={order_id}",
    "societyeats.com return url"
  );
  assert(cashfreeReturnUrl({ origin: "https://evil.example", orderId: "abc" }) === null, "foreign return url rejected");

  const previous = await prisma.appSetting.findUnique({
    where: { key: PAYMENT_PROVIDER_KEY },
  });
  const previousId = process.env.CASHFREE_CLIENT_ID;
  const previousSecret = process.env.CASHFREE_CLIENT_SECRET;
  process.env.CASHFREE_CLIENT_ID = "test-client";
  process.env.CASHFREE_CLIENT_SECRET = SECRET;

  const app = express();
  app.use(
    express.json({
      verify: (req, _res, buf) => {
        if (String(req.originalUrl || "").startsWith("/webhooks/cashfree")) {
          req.rawBody = buf.toString("utf8");
        }
      },
    })
  );
  app.use("/payments", paymentRoutes);
  app.use("/admin", adminRoutes);
  app.use("/webhooks", webhookRoutes);
  app.use((error, _req, res, _next) => {
    res.status(error.statusCode || 500).json({ error: error.message });
  });
  const server = await new Promise((resolve) => {
    const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
  });

  const createdOrderIds = [];
  const state = { vendorStatus: "IN_KYC_REVIEW", splitError: null };
  const calls = installFetch(state);

  try {
    await prisma.appSetting.deleteMany({ where: { key: PAYMENT_PROVIDER_KEY } });
    const society = await prisma.society.findFirst();
    assert(society, "seed society required");

    const buyer = await prisma.user.upsert({
      where: { phone: BUYER_PHONE },
      update: { role: "buyer", societyId: society.id, suspended: false },
      create: {
        phone: BUYER_PHONE,
        name: "Pay Buyer",
        role: "buyer",
        societyId: society.id,
      },
    });
    const seller = await prisma.user.upsert({
      where: { phone: SELLER_PHONE },
      update: {
        role: "seller",
        societyId: society.id,
        suspended: false,
        upiId: "seller@upi",
        name: "Pay Seller",
      },
      create: {
        phone: SELLER_PHONE,
        name: "Pay Seller",
        role: "seller",
        societyId: society.id,
        upiId: "seller@upi",
        paymentEnabled: true,
      },
    });
    const admin = await prisma.user.upsert({
      where: { phone: ADMIN_PHONE },
      update: { role: "super_admin", societyId: society.id, consoleAdmin: true },
      create: {
        phone: ADMIN_PHONE,
        name: "Pay Admin",
        role: "super_admin",
        societyId: society.id,
        consoleAdmin: true,
      },
    });
    const buyerToken = signToken(buyer);
    const sellerToken = signToken(seller);
    const adminToken = signToken(admin);

    const listing = await prisma.listing.create({
      data: {
        sellerId: seller.id,
        societyId: society.id,
        name: `Pay test ${Date.now()}`,
        price: 90,
      },
    });

    async function makeOrder(overrides) {
      const order = await prisma.order.create({
        data: {
          orderNumber: `SE-PAY-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
          buyerId: buyer.id,
          societyId: society.id,
          status: "accepted",
          paymentMethod: "upi",
          paymentStatus: "pending",
          subtotal: 90,
          communityFee: 10,
          total: 100,
          items: {
            create: [{ listingId: listing.id, quantity: 1, unitPrice: 90 }],
          },
          ...overrides,
        },
      });
      createdOrderIds.push(order.id);
      return order;
    }

    const direct = await makeOrder();
    const marked = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${direct.id}/mark-paid`,
      token: buyerToken,
      body: {},
    });
    assert(marked.status === 200, `direct mark-paid ${marked.status} ${JSON.stringify(marked.json)}`);
    assert(marked.json.paymentStatus === "buyer_marked_paid", "direct order still marks paid");

    const gateway = await makeOrder({ paymentProvider: "cashfree" });
    const rejected = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${gateway.id}/mark-paid`,
      token: buyerToken,
      body: {},
    });
    assert(rejected.status === 400, "cashfree mark-paid rejected");
    const rejectedConfirm = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${gateway.id}/confirm`,
      token: sellerToken,
      body: {},
    });
    assert(rejectedConfirm.status === 400, "cashfree seller confirm rejected");

    const settings = await jsonRequest(server, {
      method: "GET",
      path: "/admin/settings",
      token: adminToken,
    });
    assert(settings.status === 200, "admin settings");
    assert(settings.json.paymentProvider === "direct_upi", "missing setting is direct UPI");

    await prisma.appSetting.upsert({
      where: { key: PAYMENT_PROVIDER_KEY },
      update: { value: "payu" },
      create: { key: PAYMENT_PROVIDER_KEY, value: "payu" },
    });
    const unknown = await jsonRequest(server, {
      method: "GET",
      path: "/admin/settings",
      token: adminToken,
    });
    assert(unknown.json.paymentProvider === "direct_upi", "unknown setting is direct UPI");

    const bad = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: adminToken,
      body: { paymentProvider: "razorpay" },
    });
    assert(bad.status === 400, "unknown provider rejected");

    const buyerPatch = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: buyerToken,
      body: { paymentProvider: "cashfree" },
    });
    assert(buyerPatch.status === 403, "buyer cannot change provider");

    const turnedOn = await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: adminToken,
      body: { paymentProvider: "cashfree" },
    });
    assert(turnedOn.status === 200 && turnedOn.json.paymentProvider === "cashfree", "admin enables cashfree");

    const fresh = await makeOrder();
    const checkout = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${fresh.id}/checkout`,
      token: buyerToken,
      body: { returnOrigin: "http://localhost:49702" },
    });
    assert(checkout.status === 200, `checkout ${checkout.status} ${JSON.stringify(checkout.json)}`);
    assert(checkout.json.paymentProvider === "cashfree", "checkout locks cashfree");
    assert(checkout.json.gatewayUpiLink.includes("cashfree.com"), "cashfree link");
    const created = orderCreates(calls).find((call) =>
      String((call.body && call.body.order_meta && call.body.order_meta.return_url) || "").includes(fresh.id)
    );
    assert(created, "checkout sends a return url");
    assert(
      created.body.order_meta.return_url.includes("order_id={order_id}"),
      "cashfree return placeholder"
    );
    const creates = orderCreates(calls);
    assert(creates.length === 1, "one Cashfree order");
    assert(creates[0].body.order_id === fresh.orderNumber, "Cashfree order id is the SocietyEats order number");
    assert(creates[0].body.order_amount === 100, "Cashfree amount is the order total");

    await jsonRequest(server, {
      method: "PATCH",
      path: "/admin/settings",
      token: adminToken,
      body: { paymentProvider: "direct_upi" },
    });
    const again = await jsonRequest(server, {
      method: "POST",
      path: `/payments/${fresh.id}/checkout`,
      token: buyerToken,
      body: {},
    });
    assert(again.json.paymentProvider === "cashfree", "switch off does not change a locked order");
    assert(orderCreates(calls).length === 1, "no second Cashfree order");

    const stored = await prisma.order.findUnique({ where: { id: fresh.id } });
    const payload = JSON.stringify({
      type: "PAYMENT_SUCCESS_WEBHOOK",
      data: {
        order: { order_id: stored.orderNumber, order_amount: 100 },
        payment: { cf_payment_id: "987", payment_status: "SUCCESS" },
      },
    });
    const badHook = await jsonRequest(server, {
      method: "POST",
      path: "/webhooks/cashfree",
      body: payload,
      headers: {
        "x-webhook-timestamp": "100",
        "x-webhook-signature": "bad",
      },
    });
    assert(badHook.status === 401, "bad webhook signature ignored");
    const stillPending = await prisma.order.findUnique({ where: { id: fresh.id } });
    assert(stillPending.paymentStatus === "pending", "bad signature does not mark paid");

    await prisma.sellerPayoutProfile.upsert({
      where: { userId: seller.id },
      update: { vendorId: "se-test-vendor", vendorStatus: "IN_KYC_REVIEW", pan: "ABCDE1234F", settlementMode: "upi" },
      create: {
        userId: seller.id,
        pan: "ABCDE1234F",
        settlementMode: "upi",
        vendorId: "se-test-vendor",
        vendorStatus: "IN_KYC_REVIEW",
      },
    });

    const timestamp = "200";
    const signature = signCashfreeBody(payload, timestamp, SECRET);
    const goodHook = await jsonRequest(server, {
      method: "POST",
      path: "/webhooks/cashfree",
      body: payload,
      headers: {
        "x-webhook-timestamp": timestamp,
        "x-webhook-signature": signature,
      },
    });
    assert(goodHook.status === 200, `webhook ${goodHook.status}`);
    const paid = await prisma.order.findUnique({ where: { id: fresh.id } });
    assert(paid.paymentStatus === "paid", "webhook marks paid");
    assert(paid.splitStatus === "pending", "split waits for an active vendor");
    assert(splitCalls(calls).length === 0, "split not sent while vendor is inactive");

    state.vendorStatus = "ACTIVE";
    const retry = await jsonRequest(server, {
      method: "POST",
      path: "/webhooks/cashfree",
      body: payload,
      headers: {
        "x-webhook-timestamp": timestamp,
        "x-webhook-signature": signature,
      },
    });
    assert(retry.status === 200, "webhook retry");
    const split = await prisma.order.findUnique({ where: { id: fresh.id } });
    assert(split.splitStatus === "created", "split created once vendor is active");
    assert(splitCalls(calls).length === 1, "one split call");
    assert(splitCalls(calls)[0].body.split[0].amount === 90, "split amount is total minus fee");
    assert(splitCalls(calls)[0].body.split[0].vendor_id === "se-test-vendor", "split vendor");

    const third = await jsonRequest(server, {
      method: "POST",
      path: "/webhooks/cashfree",
      body: payload,
      headers: {
        "x-webhook-timestamp": timestamp,
        "x-webhook-signature": signature,
      },
    });
    assert(third.status === 200, "second retry");
    assert(splitCalls(calls).length === 1, "split is not sent again");

    state.splitError = new PaymentHttpError(
      "Total split amount can not be greater than transaction amount / eligible split balance",
      400,
      {}
    );
    const oversized = await makeOrder({
      paymentProvider: "cashfree",
      gatewayAmount: 100,
      paymentStatus: "paid",
      splitStatus: "pending",
    });
    const oversizedPayload = JSON.stringify({
      type: "PAYMENT_SUCCESS_WEBHOOK",
      data: {
        order: { order_id: oversized.orderNumber },
        payment: { cf_payment_id: "111", payment_status: "SUCCESS" },
      },
    });
    const oversizedSignature = signCashfreeBody(oversizedPayload, "300", SECRET);
    const oversizedHook = await jsonRequest(server, {
      method: "POST",
      path: "/webhooks/cashfree",
      body: oversizedPayload,
      headers: {
        "x-webhook-timestamp": "300",
        "x-webhook-signature": oversizedSignature,
      },
    });
    assert(oversizedHook.status === 200, "eligible-balance webhook accepted");
    const failedSplit = await prisma.order.findUnique({ where: { id: oversized.id } });
    assert(failedSplit.splitStatus === "failed", "eligible balance is recorded as a failed split");
    assert(
      /eligible split balance/i.test(failedSplit.splitError || ""),
      "split error kept"
    );

    const pendingList = await jsonRequest(server, {
      method: "GET",
      path: "/admin/payment-splits",
      token: adminToken,
    });
    assert(pendingList.status === 200, "pending splits");
    assert(
      pendingList.json.splits.some((row) => row.orderNumber === oversized.orderNumber),
      "failed split is visible to the admin"
    );

    console.log("payment-provider tests passed");
  } finally {
    resetPaymentFetch();
    if (previousId === undefined) delete process.env.CASHFREE_CLIENT_ID;
    else process.env.CASHFREE_CLIENT_ID = previousId;
    if (previousSecret === undefined) delete process.env.CASHFREE_CLIENT_SECRET;
    else process.env.CASHFREE_CLIENT_SECRET = previousSecret;
    if (createdOrderIds.length) {
      await prisma.orderItem.deleteMany({ where: { orderId: { in: createdOrderIds } } });
      await prisma.order.deleteMany({ where: { id: { in: createdOrderIds } } });
    }
    await prisma.sellerPayoutProfile.deleteMany({
      where: { user: { phone: SELLER_PHONE } },
    });
    await prisma.listing.deleteMany({
      where: { seller: { phone: SELLER_PHONE }, name: { startsWith: "Pay test " } },
    });
    if (previous) {
      await prisma.appSetting.upsert({
        where: { key: PAYMENT_PROVIDER_KEY },
        update: { value: previous.value },
        create: { key: PAYMENT_PROVIDER_KEY, value: previous.value },
      });
    } else {
      await prisma.appSetting.deleteMany({ where: { key: PAYMENT_PROVIDER_KEY } });
    }
    await new Promise((resolve) => server.close(() => resolve()));
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
