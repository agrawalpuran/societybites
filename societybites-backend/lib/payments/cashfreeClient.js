const { httpError } = require("./providers");

class PaymentHttpError extends Error {
  constructor(message, status, body) {
    super(message);
    this.statusCode = status >= 500 ? 502 : status || 502;
    this.body = body;
  }
}

let fetchImpl = defaultFetch;

function setPaymentFetch(fn) {
  fetchImpl = fn;
}

function resetPaymentFetch() {
  fetchImpl = defaultFetch;
}

async function defaultFetch(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (_) {
    json = null;
  }
  if (!response.ok) {
    const message =
      (json && (json.message || json.error)) || text || response.statusText;
    throw new PaymentHttpError(message, response.status, json);
  }
  return json;
}

function cashfreeConfig() {
  const envName = String(process.env.CASHFREE_ENV || "sandbox").toLowerCase();
  const production = envName === "production";
  return {
    clientId: process.env.CASHFREE_CLIENT_ID || "",
    clientSecret: process.env.CASHFREE_CLIENT_SECRET || "",
    env: production ? "production" : "sandbox",
    baseUrl: production
      ? "https://api.cashfree.com"
      : "https://sandbox.cashfree.com",
  };
}

function assertCashfreeConfigured(config) {
  if (!config.clientId || !config.clientSecret) {
    throw httpError(503, "Cashfree is not configured");
  }
}

async function cashfreeRequest({ method, path, body, config, headers }) {
  const version = path.includes("/easy-split/") ? "2022-09-01" : "2023-08-01";
  return fetchImpl(`${config.baseUrl}${path}`, {
    method,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "x-api-version": version,
      "x-client-id": config.clientId,
      "x-client-secret": config.clientSecret,
      ...(headers || {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

function customerPhone(phone) {
  const digits = String(phone || "").replace(/\D/g, "");
  return digits.slice(-10);
}

function cashfreeReturnUrl({ origin, orderId }) {
  if (!origin || !orderId) return null;
  let parsed;
  try {
    parsed = new URL(String(origin));
  } catch {
    return null;
  }
  const host = parsed.hostname;
  const local = host === "localhost" || host === "127.0.0.1";
  const publicHost =
    host === "societyeats.com" ||
    host === "www.societyeats.com" ||
    host === "societyeats.vercel.app";
  if (local) {
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
  } else if (!(parsed.protocol === "https:" && publicHost)) {
    return null;
  }
  const order = encodeURIComponent(String(orderId));
  // Cashfree replaces {order_id} when it sends the browser back.
  return `${parsed.origin}/pay/return?order=${order}&order_id={order_id}`;
}

async function createCashfreeOrder({ order, amount, config, returnUrl }) {
  const phone = customerPhone(order.buyer && order.buyer.phone);
  if (phone.length !== 10) {
    throw httpError(400, "Buyer phone is required for Cashfree");
  }
  const payload = {
    order_id: order.orderNumber,
    order_amount: amount,
    order_currency: "INR",
    order_note: order.orderNumber,
    customer_details: {
      customer_id: String(order.buyerId).replace(/-/g, "").slice(0, 50),
      customer_phone: phone,
      customer_name: (order.buyer && order.buyer.name) || "SocietyEats buyer",
    },
    ...(returnUrl ? { order_meta: { return_url: returnUrl } } : {}),
  };
  try {
    return await cashfreeRequest({
      method: "POST",
      path: "/pg/orders",
      body: payload,
      config,
    });
  } catch (error) {
    if (error instanceof PaymentHttpError && error.statusCode === 409) {
      return { payment_session_id: null, order_id: order.orderNumber, existing: true };
    }
    throw error;
  }
}

function readQrPayload(payResponse) {
  const data = (payResponse && payResponse.data) || {};
  const payload = data.payload || {};
  return (
    payload.upi ||
    payload.qrcode ||
    payload.qr ||
    data.upi ||
    null
  );
}

function readUpiLink(payResponse) {
  const data = (payResponse && payResponse.data) || {};
  const payload = data.payload || {};
  return data.url || payload.default || payload.upi || payload.web || null;
}

async function createCashfreeUpiSession({ order, amount, config, returnUrl }) {
  assertCashfreeConfigured(config);
  const created = await createCashfreeOrder({ order, amount, config, returnUrl });
  let sessionId = created && created.payment_session_id;
  if (!sessionId) {
    const existing = await cashfreeRequest({
      method: "GET",
      path: `/pg/orders/${encodeURIComponent(order.orderNumber)}`,
      config,
    });
    sessionId = existing && existing.payment_session_id;
  }
  if (!sessionId) {
    throw httpError(502, "Cashfree did not return a payment session");
  }
  const payBody = (channel) => ({
    payment_session_id: sessionId,
    payment_method: { upi: { channel } },
  });
  // Order Pay lives at /pg/orders/sessions. /pg/orders/pay answers
  // "token is not present" even when payment_session_id is in the body.
  const payHeaders = {
    "x-client-device": "desktop",
    "x-client-os": "windows",
    "x-client-browser": "chrome",
  };
  const [qrPay, linkPay] = await Promise.all([
    cashfreeRequest({
      method: "POST",
      path: "/pg/orders/sessions",
      body: payBody("qrcode"),
      headers: payHeaders,
      config,
    }),
    cashfreeRequest({
      method: "POST",
      path: "/pg/orders/sessions",
      body: payBody("link"),
      headers: payHeaders,
      config,
    }),
  ]);
  return {
    gatewayQrPayload: readQrPayload(qrPay),
    gatewayUpiLink: readUpiLink(linkPay) || readUpiLink(qrPay),
    gatewayPaymentId:
      (linkPay && (linkPay.cf_payment_id || linkPay.payment_id)) ||
      (qrPay && (qrPay.cf_payment_id || qrPay.payment_id)) ||
      null,
  };
}

function vendorIdForUser(userId) {
  return `se${String(userId).replace(/-/g, "")}`.slice(0, 50);
}

function vendorBody({ user, profile, vendorId }) {
  const phone = customerPhone(user.phone);
  const body = {
    vendor_id: vendorId,
    status: "ACTIVE",
    name: user.name || "SocietyEats seller",
    email: `seller.${phone || "unknown"}@example.com`,
    phone: phone || "9999999999",
    verify_account: true,
    dashboard_access: false,
    schedule_option: 2,
    kyc_details: {
      account_type: "Individual",
      business_type: "Food and Beverages",
      pan: profile.pan,
    },
  };
  if (profile.settlementMode === "bank") {
    body.bank = {
      account_number: profile.accountNumber,
      account_holder: profile.accountHolder,
      ifsc: profile.ifsc,
    };
  } else {
    body.upi = {
      vpa: user.upiId,
      account_holder: profile.accountHolder || user.upiDisplayName || user.name || "Seller",
    };
  }
  return body;
}

async function upsertCashfreeVendor({ user, profile, config }) {
  assertCashfreeConfigured(config);
  const vendorId = profile.vendorId || vendorIdForUser(user.id);
  const body = vendorBody({ user, profile, vendorId });
  const path = profile.vendorId
    ? `/pg/easy-split/vendors/${encodeURIComponent(vendorId)}`
    : "/pg/easy-split/vendors";
  const method = profile.vendorId ? "PATCH" : "POST";
  const response = await cashfreeRequest({ method, path, body, config });
  return {
    vendorId,
    vendorStatus: (response && response.status) || "IN_KYC_REVIEW",
  };
}

async function fetchCashfreeVendor({ vendorId, config }) {
  assertCashfreeConfigured(config);
  return cashfreeRequest({
    method: "GET",
    path: `/pg/easy-split/vendors/${encodeURIComponent(vendorId)}`,
    config,
  });
}

async function splitCashfreeOrder({ orderNumber, vendorId, amount, config }) {
  assertCashfreeConfigured(config);
  return cashfreeRequest({
    method: "POST",
    path: `/pg/easy-split/orders/${encodeURIComponent(orderNumber)}/split`,
    body: {
      split: [
        {
          vendor_id: vendorId,
          amount,
          tags: { order_id: orderNumber },
        },
      ],
      disable_split: true,
    },
    config,
  });
}

module.exports = {
  PaymentHttpError,
  setPaymentFetch,
  resetPaymentFetch,
  cashfreeConfig,
  cashfreeReturnUrl,
  createCashfreeUpiSession,
  upsertCashfreeVendor,
  fetchCashfreeVendor,
  splitCashfreeOrder,
  vendorIdForUser,
};
