const {
  SELLER,
  PROROUTING,
  normalizeDeliveryProvider,
  parseAllowlist,
  allowlistAllows,
  isProroutingEnvConfigured,
  toProroutingPhone,
} = require("../lib/delivery/deliverySetting");
const { evaluatePartnerDelivery } = require("../lib/delivery/eligibility");
const {
  mapProroutingState,
  isOlderThan,
  applyWebhookToTask,
  partnerSearchAction,
} = require("../lib/delivery/webhookStatus");
const {
  setDeliveryFetch,
  resetDeliveryFetch,
  createOrder,
} = require("../lib/delivery/proroutingClient");
const {
  serializeDelivery,
  parseEstimateQuote,
  estimateIdFromTask,
  shouldAutoCompletePartnerOrder,
  partnerTaskAllowsSellerComplete,
} = require("../lib/delivery/deliveryService");
const { isEligibleDelayedDeliveryCharge } = require("../lib/delayedDeliveryCharge");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const societyA = {
  latitude: 12.97,
  longitude: 77.59,
  pincode: "560076",
  city: "Bengaluru",
  state: "Karnataka",
};
const societyB = {
  latitude: 12.93,
  longitude: 77.61,
  pincode: "560102",
  city: "Bengaluru",
  state: "Karnataka",
};

function baseEval(overrides) {
  return evaluatePartnerDelivery({
    provider: PROROUTING,
    allowlist: ["+919800000001", "+919800000002"],
    buyerPhone: "+919800000001",
    sellerPhone: "+919800000002",
    orderType: "regular",
    isCrossSociety: true,
    fulfilmentMethod: "seller_delivery",
    paymentMethod: "upi",
    pickupSociety: societyA,
    dropSociety: societyB,
    env: {
      PROROUTING_API_KEY: "test",
      PROROUTING_BASE_URL: "https://preprod.example",
    },
    ...overrides,
  });
}

async function main() {
  assert(normalizeDeliveryProvider(null) === SELLER, "missing provider is seller");
  assert(normalizeDeliveryProvider("cashfree") === SELLER, "unknown is seller");
  assert(normalizeDeliveryProvider("PROROUTING") === PROROUTING, "prorouting on");

  assert(parseAllowlist("").length === 0, "empty allowlist");
  assert(parseAllowlist("not-json").length === 0, "invalid json allowlist");
  const phones = parseAllowlist(["9800000001", "+919800000001"]);
  assert(phones.length === 1 && phones[0] === "+919800000001", "dedupe allowlist");
  const fromCsv = parseAllowlist("+919800000001, 9800000002");
  assert(
    fromCsv.length === 2 &&
      fromCsv[0] === "+919800000001" &&
      fromCsv[1] === "+919800000002",
    "comma-separated allowlist"
  );
  const testDigits = parseAllowlist(["2222222222"]);
  assert(
    testDigits.length === 1 && testDigits[0] === "+912222222222",
    "allowlist accepts any 10 digits"
  );
  assert(
    toProroutingPhone("+919800000001") === "9800000001",
    "prorouting phone is 10 digits"
  );

  const quote = parseEstimateQuote({
    status: 1,
    estimate: { id: "est_1", price: 3.54 },
  });
  assert(quote && quote.price === 3.54 && quote.estimateId === "est_1", "parse estimate");
  const liveQuote = parseEstimateQuote({
    status: 1,
    estimate_id: "est_live",
    price: 3.54,
    fees: {},
  });
  assert(
    liveQuote && liveQuote.price === 3.54 && liveQuote.estimateId === "est_live",
    "parse live estimate shape"
  );
  assert(parseEstimateQuote({ status: 0, message: "no" }) === null, "failed estimate");
  assert(
    estimateIdFromTask({
      lastPayload: JSON.stringify({ estimateId: "est_1" }),
    }) === "est_1",
    "estimate id from task"
  );

  assert(
    !allowlistAllows([], "+919800000001", "+919800000002"),
    "empty allowlist blocks"
  );
  assert(
    allowlistAllows(
      ["+919800000001", "+919800000002"],
      "9800000001",
      "9800000002"
    ),
    "both phones pass"
  );
  assert(
    !allowlistAllows(
      ["+919800000001", "+919800000002"],
      "+919800000001",
      "+919800000099"
    ),
    "seller must match"
  );

  assert(!isProroutingEnvConfigured({}), "env missing");
  assert(
    isProroutingEnvConfigured({
      PROROUTING_API_KEY: "k",
      PROROUTING_BASE_URL: "https://x",
    }),
    "env present"
  );

  assert(baseEval().useProrouting === true, "eligible books");
  assert(baseEval({ provider: SELLER }).useProrouting === false, "toggle off");
  assert(
    baseEval({ allowlist: [] }).useProrouting === false,
    "empty allowlist even if on"
  );
  assert(
    baseEval({ isCrossSociety: false }).useProrouting === false,
    "in-society skip"
  );
  assert(
    baseEval({ paymentMethod: "cash" }).useProrouting === false,
    "cash skip"
  );
  assert(
    baseEval({ pickupSociety: { ...societyA, pincode: null } }).useProrouting ===
      false,
    "no pincode skip"
  );
  assert(
    baseEval({ env: {} }).useProrouting === false,
    "missing env skip"
  );

  assert(mapProroutingState("UnFulfilled") === "booked", "map unfulfilled");
  assert(mapProroutingState("Agent-assigned") === "assigned", "map assigned");
  assert(mapProroutingState("At-pickup") === "at_pickup", "map at pickup");
  assert(mapProroutingState("Order-picked-up") === "picked_up", "map picked up");
  assert(mapProroutingState("At--delivery") === "at_delivery", "map at delivery");
  assert(mapProroutingState("Order-delivered") === "delivered", "map delivered");
  assert(isOlderThan("delivered", "assigned") === true, "older ignored");
  assert(isOlderThan("booked", "assigned") === false, "newer applied");
  const hunt = {
    state: "booked",
    bookedAt: new Date(1_000_000),
    retryCount: 0,
    createdAt: new Date(1_000_000),
  };
  assert(
    partnerSearchAction(hunt, 1_000_000 + 14 * 60 * 1000, {
      retryAfterMs: 15 * 60 * 1000,
      fallbackAfterMs: 60 * 60 * 1000,
    }) === "none",
    "under 15 min no retry"
  );
  assert(
    partnerSearchAction(hunt, 1_000_000 + 16 * 60 * 1000, {
      retryAfterMs: 15 * 60 * 1000,
      fallbackAfterMs: 60 * 60 * 1000,
    }) === "retry",
    "15 min retries once"
  );
  assert(
    partnerSearchAction(
      { ...hunt, retryCount: 1 },
      1_000_000 + 16 * 60 * 1000,
      {
        retryAfterMs: 15 * 60 * 1000,
        fallbackAfterMs: 60 * 60 * 1000,
      }
    ) === "none",
    "second auto-retry skipped"
  );
  assert(
    partnerSearchAction(hunt, 1_000_000 + 61 * 60 * 1000, {
      retryAfterMs: 15 * 60 * 1000,
      fallbackAfterMs: 60 * 60 * 1000,
    }) === "fallback",
    "60 min seller fallback"
  );
  const staleId = applyWebhookToTask(
    { state: "retrying", externalId: "new_1" },
    { order: { id: "old_1", state: "UnFulfilled" } }
  );
  assert(staleId.ignored === true, "old prorouting id ignored after rebook");

  const older = applyWebhookToTask(
    { state: "delivered" },
    { order: { state: "Agent-assigned", rider: { name: "A" } } }
  );
  assert(older.ignored === true, "stale webhook ignored");
  const newer = applyWebhookToTask(
    { state: "booked" },
    {
      order: {
        state: "Agent-assigned",
        id: "pro_1",
        rider: { name: "Ravi", phone: "999" },
        lsp: { name: "Rapido" },
        price: 58,
      },
    }
  );
  assert(newer.ignored === false, "fresh webhook applied");
  assert(newer.task.state === "assigned", "state assigned");
  assert(newer.task.riderName === "Ravi", "rider copied");

  const deliveredCb = applyWebhookToTask(
    { state: "picked_up" },
    {
      order: {
        state: "Order-delivered",
        tracking_url: "https://track.example/abc",
      },
    }
  );
  assert(deliveredCb.task.trackingUrl === "https://track.example/abc", "tracking_url mapped");

  const retry = applyWebhookToTask(
    { state: "assigned" },
    { order: { state: "UnFulfilled" } }
  );
  assert(retry.ignored === false, "lsp cancel can return to unfulfilled");
  assert(retry.task.state === "booked", "rebroadcast maps to booked");

  const otpTask = {
    provider: PROROUTING,
    state: "assigned",
    pickupOtp: "1111",
    dropOtp: "2222",
    quotedFare: 40,
    billedFare: 42,
  };
  const buyerView = serializeDelivery(otpTask, {
    viewerUserId: "b",
    buyerId: "b",
    sellerId: "s",
  });
  assert(buyerView.dropOtp === "2222", "buyer sees drop otp");
  assert(buyerView.pickupOtp === null, "buyer never sees pickup otp");
  assert(buyerView.quotedFare === null, "buyer does not see fare");
  const sellerView = serializeDelivery(otpTask, {
    viewerUserId: "s",
    buyerId: "b",
    sellerId: "s",
  });
  assert(sellerView.pickupOtp === "1111", "seller sees pickup otp");
  assert(sellerView.dropOtp === null, "seller never sees drop otp");
  assert(sellerView.quotedFare === 40, "seller sees quoted fare");
  assert(buyerView.lastError === null, "buyer does not see lastError");
  const failedSeller = serializeDelivery(
    { ...otpTask, lastError: "pickup.phone" },
    { viewerUserId: "s", buyerId: "b", sellerId: "s" }
  );
  assert(failedSeller.lastError === "pickup.phone", "seller sees lastError");

  assert(
    partnerTaskAllowsSellerComplete("at_pickup") === false,
    "seller complete blocked while rider in flight"
  );
  assert(
    partnerTaskAllowsSellerComplete("delivered") === true,
    "seller complete after delivered"
  );
  assert(
    partnerTaskAllowsSellerComplete("failed") === true,
    "seller complete if partner failed"
  );
  const partnerReady = {
    status: "ready",
    deliveryProvider: "prorouting",
    paymentMethod: "upi",
    paymentStatus: "seller_confirmed",
  };
  assert(
    shouldAutoCompletePartnerOrder(partnerReady, "delivered") === true,
    "delivered ready partner auto-completes"
  );
  assert(
    shouldAutoCompletePartnerOrder(partnerReady, "at_delivery") === false,
    "not delivered yet"
  );
  assert(
    shouldAutoCompletePartnerOrder(
      { ...partnerReady, status: "accepted" },
      "delivered"
    ) === false,
    "not ready yet"
  );

  assert(
    isEligibleDelayedDeliveryCharge({
      type: "regular",
      fulfilmentMethod: "seller_delivery",
      societyId: "a",
      deliveryProvider: "prorouting",
      items: [{ listing: { societyId: "b" } }],
    }) === false,
    "partner order skips delayed charge"
  );
  assert(
    isEligibleDelayedDeliveryCharge({
      type: "regular",
      fulfilmentMethod: "seller_delivery",
      societyId: "a",
      items: [{ listing: { societyId: "b" } }],
    }) === true,
    "today delayed charge still on"
  );

  let called = 0;
  setDeliveryFetch(async (url, options) => {
    called += 1;
    assert(url.endsWith("/partner/order/createasync"), url);
    assert(options.headers["x-pro-api-key"] === "k", "api key header");
    return { status: 1, order: { id: "pro_x", state: "UnFulfilled" } };
  });
  try {
    const res = await createOrder(
      { client_order_id: "o1" },
      { apiKey: "k", baseUrl: "https://preprod.example" }
    );
    assert(res.order.id === "pro_x", "create response");
    assert(called === 1, "one http call");
  } finally {
    resetDeliveryFetch();
  }

  console.log("delivery-prorouting tests passed");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
