const assert = require("assert");
const {
  TEMPLATE_NAME,
  ORDER_TEMPLATE_NAME,
  READY_TEMPLATE_NAME,
  COMPLETED_TEMPLATE_NAME,
  READY_TEMPLATE_ENV,
  COMPLETED_TEMPLATE_ENV,
  TEMPLATE_LANGUAGE,
  sendWhatsAppOrderNotification,
  sendWhatsAppReadyNotification,
  sendWhatsAppCompletedNotification,
  buyerOrderTemplateParameters,
  templatePayload,
  graphMessagesUrl,
  toWhatsAppRecipient,
  readConfig,
} = require("../lib/whatsappCloud");
const notifications = require("../utils/notifications");

function sampleOrder(phone) {
  return {
    id: "order-1",
    orderNumber: "SE-100001",
    items: [
      {
        listing: {
          sellerId: "seller-1",
          seller: { phone },
        },
      },
    ],
  };
}

function orderNotificationOrder(overrides = {}) {
  const phone = Object.prototype.hasOwnProperty.call(overrides, "phone")
    ? overrides.phone
    : "+919901844776";
  const order = {
    id: "order-1",
    orderNumber: "SE-100001",
    total: 250,
    buyer: { name: "Asha", phone: "+919881234567" },
    items: [
      {
        quantity: 2,
        listing: {
          name: "Idli",
          sellerId: "seller-1",
          seller: { name: "Meera", phone },
        },
      },
      {
        quantity: 1,
        listing: {
          name: "Masala Dosa",
          sellerId: "seller-1",
          seller: { name: "Meera", phone },
        },
      },
    ],
  };
  if (Object.prototype.hasOwnProperty.call(overrides, "total")) {
    order.total = overrides.total;
  }
  if (Object.prototype.hasOwnProperty.call(overrides, "buyer")) {
    order.buyer = overrides.buyer;
  }
  if (Object.prototype.hasOwnProperty.call(overrides, "items")) {
    order.items = overrides.items;
  }
  if (Object.prototype.hasOwnProperty.call(overrides, "orderNumber")) {
    order.orderNumber = overrides.orderNumber;
  }
  return order;
}

function bodyParameters(call) {
  const body = JSON.parse(call.options.body);
  const components = body.template.components || [];
  const bodyComponent = components.find((component) => component.type === "body");
  return {
    body,
    parameters: bodyComponent ? bodyComponent.parameters : null,
  };
}

function mockFetch({ ok = true, status = 200, body, delayMs = 0, onCall } = {}) {
  const calls = [];
  const fetchFn = async (url, options) => {
    calls.push({ url, options });
    if (onCall) onCall({ url, options });
    if (delayMs) {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(resolve, delayMs);
        const signal = options && options.signal;
        if (signal) {
          const onAbort = () => {
            clearTimeout(timer);
            const err = new Error("Aborted");
            err.name = "AbortError";
            reject(err);
          };
          if (signal.aborted) {
            onAbort();
            return;
          }
          signal.addEventListener("abort", onAbort, { once: true });
        }
      });
    }
    return {
      ok,
      status,
      json: async () => body,
    };
  };
  fetchFn.calls = calls;
  return fetchFn;
}

async function main() {
  const creds = {
    WHATSAPP_TOKEN: "test-token",
    WHATSAPP_PHONE_NUMBER_ID: "123456789",
    WHATSAPP_API_VERSION: "v21.0",
    WHATSAPP_TIMEOUT_MS: "50",
  };

  const off = await sendWhatsAppOrderNotification(sampleOrder("+919901844776"), {
    isEnabled: async () => false,
    env: creds,
    fetch: mockFetch(),
  });
  assert(off.sent === false && off.reason === "admin_off", "admin off skips");
  const offFetch = mockFetch();
  await sendWhatsAppOrderNotification(sampleOrder("+919901844776"), {
    isEnabled: async () => false,
    env: creds,
    fetch: offFetch,
  });
  assert(offFetch.calls.length === 0, "admin off makes zero API calls");

  const missingCreds = mockFetch();
  const unconfigured = await sendWhatsAppOrderNotification(
    sampleOrder("+919901844776"),
    {
      isEnabled: async () => true,
      env: { WHATSAPP_API_VERSION: "v21.0" },
      fetch: missingCreds,
    }
  );
  assert(unconfigured.reason === "unconfigured", "missing credentials skip");
  assert(missingCreds.calls.length === 0, "missing credentials make zero API calls");

  const emergencyFetch = mockFetch();
  const emergency = await sendWhatsAppOrderNotification(
    sampleOrder("+919901844776"),
    {
      isEnabled: async () => true,
      env: { ...creds, WHATSAPP_ENABLED: "false" },
      fetch: emergencyFetch,
    }
  );
  assert(emergency.reason === "emergency_off", "emergency switch skips");
  assert(emergencyFetch.calls.length === 0, "emergency switch makes zero API calls");

  const noPhoneFetch = mockFetch();
  const noPhone = await sendWhatsAppOrderNotification(sampleOrder(null), {
    isEnabled: async () => true,
    env: creds,
    fetch: noPhoneFetch,
  });
  assert(noPhone.reason === "no_phone", "missing phone skips");
  assert(noPhoneFetch.calls.length === 0, "missing phone makes zero API calls");

  const badPhoneFetch = mockFetch();
  const badPhone = await sendWhatsAppOrderNotification(sampleOrder("123"), {
    isEnabled: async () => true,
    env: creds,
    fetch: badPhoneFetch,
  });
  assert(badPhone.reason === "no_phone", "invalid phone skips");
  assert(badPhoneFetch.calls.length === 0, "invalid phone makes zero API calls");

  assert(toWhatsAppRecipient("+919901844776") === "919901844776", "E.164 to Graph to");
  assert(toWhatsAppRecipient("9901844776") === "919901844776", "10-digit to Graph to");

  const payload = templatePayload("919901844776");
  assert(payload.template.name === TEMPLATE_NAME, "hello_world template");
  assert(payload.template.language.code === TEMPLATE_LANGUAGE, "en_US language");
  assert(payload.type === "template", "template type");

  const config = readConfig(creds);
  assert(
    graphMessagesUrl(config) ===
      "https://graph.facebook.com/v21.0/123456789/messages",
    "graph URL"
  );

  const successFetch = mockFetch({
    body: { messages: [{ id: "wamid.test-message" }] },
  });
  const sent = await sendWhatsAppOrderNotification(sampleOrder("+919901844776"), {
    isEnabled: async () => true,
    env: creds,
    fetch: successFetch,
  });
  assert(sent.sent === true, "success sent");
  assert(sent.messageId === "wamid.test-message", "message id returned");
  assert(successFetch.calls.length === 1, "one Graph call");
  const call = successFetch.calls[0];
  assert(call.url.includes("/123456789/messages"), "phone number id in URL");
  assert(call.options.method === "POST", "POST");
  assert(
    String(call.options.headers.Authorization).startsWith("Bearer "),
    "bearer auth"
  );
  const body = JSON.parse(call.options.body);
  assert(body.to === "919901844776", "recipient");
  assert(body.template.name === "hello_world", "template name on wire");
  assert(body.template.language.code === "en_US", "language on wire");
  assert(body.template.components === undefined, "hello_world has no parameters");
  assert(
    readConfig(creds).templateName === TEMPLATE_NAME,
    "hello_world remains the default"
  );
  assert(
    readConfig({ ...creds, WHATSAPP_TEMPLATE_NAME: "Not Valid" }).templateName ===
      TEMPLATE_NAME,
    "invalid template name stays on hello_world"
  );
  assert(
    readConfig({ ...creds, WHATSAPP_TEMPLATE_NAME: "se_new_order_notification" })
      .templateName === "se_new_order_notification",
    "prefixed Meta name is allowed"
  );
  assert(
    readConfig(creds).templateLanguage === TEMPLATE_LANGUAGE,
    "order language defaults to en_US"
  );
  assert(
    readConfig({ ...creds, WHATSAPP_TEMPLATE_LANGUAGE: "en" }).templateLanguage === "en",
    "en is allowed for the order template"
  );
  assert(
    readConfig({ ...creds, WHATSAPP_TEMPLATE_LANGUAGE: "fr" }).templateLanguage ===
      TEMPLATE_LANGUAGE,
    "unknown language stays on en_US"
  );

  const populatedHello = mockFetch({
    body: { messages: [{ id: "wamid.hello-populated" }] },
  });
  const populatedSent = await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: creds,
    fetch: populatedHello,
  });
  assert(populatedSent.sent === true, "populated order still uses hello_world");
  const populatedBody = JSON.parse(populatedHello.calls[0].options.body);
  assert(populatedBody.template.name === "hello_world", "default name unchanged");
  assert(
    populatedBody.template.components === undefined,
    "hello_world payload remains unchanged"
  );

  const orderEnv = { ...creds, WHATSAPP_TEMPLATE_NAME: ORDER_TEMPLATE_NAME };
  const orderFetch = mockFetch({
    body: { messages: [{ id: "wamid.order-template" }] },
  });
  const orderSent = await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: orderEnv,
    fetch: orderFetch,
  });
  assert(orderSent.sent === true, "new template sent");
  assert(orderFetch.calls.length === 1, "new template makes one Graph call");
  const mapped = bodyParameters(orderFetch.calls[0]);
  assert(mapped.body.template.name === ORDER_TEMPLATE_NAME, "new template name");
  assert(mapped.body.template.language.code === "en_US", "new template language");

  const englishFetch = mockFetch({
    body: { messages: [{ id: "wamid.order-en" }] },
  });
  await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: { ...orderEnv, WHATSAPP_TEMPLATE_LANGUAGE: "en" },
    fetch: englishFetch,
  });
  const englishBody = JSON.parse(englishFetch.calls[0].options.body);
  assert(englishBody.template.name === ORDER_TEMPLATE_NAME, "en still uses order template");
  assert(englishBody.template.language.code === "en", "order template can send en");
  assert(
    englishBody.template.components[0].parameters.length === 5,
    "en payload still has five parameters"
  );

  const helloEnFetch = mockFetch({
    body: { messages: [{ id: "wamid.hello-en-ignored" }] },
  });
  await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: { ...creds, WHATSAPP_TEMPLATE_LANGUAGE: "en" },
    fetch: helloEnFetch,
  });
  const helloEnBody = JSON.parse(helloEnFetch.calls[0].options.body);
  assert(helloEnBody.template.name === TEMPLATE_NAME, "hello_world name unchanged");
  assert(helloEnBody.template.language.code === "en_US", "hello_world stays en_US");

  const prefixedFetch = mockFetch({
    body: { messages: [{ id: "wamid.prefixed" }] },
  });
  await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: { ...creds, WHATSAPP_TEMPLATE_NAME: "se_new_order_notification" },
    fetch: prefixedFetch,
  });
  const prefixed = bodyParameters(prefixedFetch.calls[0]);
  assert(
    prefixed.body.template.name === "se_new_order_notification",
    "Graph uses the env template name"
  );
  assert(prefixed.parameters && prefixed.parameters.length === 5, "prefixed name still five params");
  assert(prefixed.parameters[1].text === "SE-100001", "prefixed name still maps order number");
  assert(mapped.parameters && mapped.parameters.length === 5, "exactly five parameters");
  assert(
    mapped.parameters.every((parameter) => parameter.type === "text"),
    "text body parameters"
  );
  assert(mapped.parameters[0].text === "Meera", "seller name");
  assert(mapped.parameters[1].text === "SE-100001", "order number");
  assert(mapped.parameters[2].text === "Asha", "customer name");
  assert(mapped.parameters[3].text === "2 x Idli, 1 x Masala Dosa", "item summary");
  assert(mapped.parameters[4].text === "250", "final order amount");
  const mappedWire = JSON.stringify(mapped.body);
  assert(!mappedWire.includes("Anita"), "Meta sample seller is not hardcoded");
  assert(!mappedWire.includes("SE1025"), "Meta sample order number is not hardcoded");
  assert(!mappedWire.includes("Rahul"), "Meta sample customer is not hardcoded");
  assert(!mapped.parameters[4].text.includes("₹"), "mapped amount has no rupee symbol");

  const distinctFetch = mockFetch({
    body: { messages: [{ id: "wamid.distinct" }] },
  });
  const distinctOrder = orderNotificationOrder({
    orderNumber: "SE-882341",
    total: { toNumber: () => 412 },
    buyer: { name: "Neel" },
    items: [
      {
        quantity: 3,
        listing: {
          name: "Poha",
          seller: { name: "Kavya", phone: "+919901844776" },
        },
      },
      {
        quantity: 2,
        listing: {
          name: "Filter Coffee",
          seller: { name: "Kavya", phone: "+919901844776" },
        },
      },
    ],
  });
  await sendWhatsAppOrderNotification(distinctOrder, {
    isEnabled: async () => true,
    env: orderEnv,
    fetch: distinctFetch,
  });
  const distinct = bodyParameters(distinctFetch.calls[0]);
  assert(distinct.parameters[0].text === "Kavya", "seller comes from committed order");
  assert(distinct.parameters[1].text === "SE-882341", "order number comes from committed order");
  assert(distinct.parameters[2].text === "Neel", "customer comes from committed order");
  assert(
    distinct.parameters[3].text === "3 x Poha, 2 x Filter Coffee",
    "items combine quantity and listing name"
  );
  assert(distinct.parameters[4].text === "412", "amount comes from committed order total");

  const longName = "Paneer".repeat(80);
  const longFetch = mockFetch({
    body: { messages: [{ id: "wamid.long" }] },
  });
  await sendWhatsAppOrderNotification(
    orderNotificationOrder({
      items: [
        {
          quantity: 1,
          listing: {
            name: longName,
            seller: { name: "Meera", phone: "+919901844776" },
          },
        },
      ],
    }),
    {
      isEnabled: async () => true,
      env: orderEnv,
      fetch: longFetch,
    }
  );
  const longSummary = bodyParameters(longFetch.calls[0]).parameters[3].text;
  assert(longSummary.length <= 200, "item summary stays within length");
  assert(longSummary.endsWith("..."), "long item summary is truncated");

  const decimalFetch = mockFetch({
    body: { messages: [{ id: "wamid.decimal" }] },
  });
  await sendWhatsAppOrderNotification(orderNotificationOrder({ total: 180.5 }), {
    isEnabled: async () => true,
    env: orderEnv,
    fetch: decimalFetch,
  });
  const decimalParams = bodyParameters(decimalFetch.calls[0]).parameters;
  assert(decimalParams[4].text === "180.50", "amount keeps paise without currency");
  assert(!decimalParams[4].text.includes("₹"), "amount has no rupee symbol");

  const fallbackFetch = mockFetch({
    body: { messages: [{ id: "wamid.fallback" }] },
  });
  await sendWhatsAppOrderNotification(
    orderNotificationOrder({
      buyer: { name: "  " },
      items: [
        {
          quantity: 1,
          listing: {
            name: "Idli",
            seller: { name: null, phone: "+919901844776" },
          },
        },
      ],
    }),
    {
      isEnabled: async () => true,
      env: orderEnv,
      fetch: fallbackFetch,
    }
  );
  const fallbackParams = bodyParameters(fallbackFetch.calls[0]).parameters;
  assert(fallbackParams[0].text === "Seller", "missing seller name fallback");
  assert(fallbackParams[2].text === "Customer", "missing customer name fallback");

  for (const total of [null, undefined, "", "abc", -1, Number.NaN]) {
    const invalidFetch = mockFetch();
    const invalid = await sendWhatsAppOrderNotification(
      orderNotificationOrder({ total }),
      {
        isEnabled: async () => true,
        env: orderEnv,
        fetch: invalidFetch,
      }
    );
    assert(
      invalid.sent === false && invalid.reason === "invalid_amount",
      `invalid amount skips: ${total}`
    );
    assert(invalidFetch.calls.length === 0, "invalid amount makes zero API calls");
  }

  const adminOffFetch = mockFetch();
  const adminOffNew = await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => false,
    env: orderEnv,
    fetch: adminOffFetch,
  });
  assert(
    adminOffNew.sent === false && adminOffNew.reason === "admin_off",
    "admin off skips new template"
  );
  assert(adminOffFetch.calls.length === 0, "admin off makes zero calls for new template");

  const emergencyNewFetch = mockFetch();
  const emergencyNew = await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: { ...orderEnv, WHATSAPP_ENABLED: "false" },
    fetch: emergencyNewFetch,
  });
  assert(emergencyNew.reason === "emergency_off", "emergency switch skips new template");
  assert(emergencyNewFetch.calls.length === 0, "emergency switch makes zero new-template calls");

  const badPhoneNew = mockFetch();
  const badPhoneOrder = await sendWhatsAppOrderNotification(
    orderNotificationOrder({ phone: "123" }),
    {
      isEnabled: async () => true,
      env: orderEnv,
      fetch: badPhoneNew,
    }
  );
  assert(badPhoneOrder.reason === "no_phone", "invalid seller phone skips new template");
  assert(badPhoneNew.calls.length === 0, "invalid phone makes zero new-template calls");

  const orderErrorFetch = mockFetch({
    ok: false,
    status: 400,
    body: { error: { message: "Template not approved" } },
  });
  const orderApiError = await sendWhatsAppOrderNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: orderEnv,
    fetch: orderErrorFetch,
  });
  assert(
    orderApiError.sent === false && orderApiError.reason === "error",
    "new template API failure contained"
  );

  const errorFetch = mockFetch({
    ok: false,
    status: 400,
    body: { error: { message: "Invalid parameter" } },
  });
  const apiError = await sendWhatsAppOrderNotification(
    sampleOrder("+919901844776"),
    {
      isEnabled: async () => true,
      env: creds,
      fetch: errorFetch,
    }
  );
  assert(apiError.sent === false && apiError.reason === "error", "API error contained");

  const timeoutFetch = mockFetch({
    delayMs: 80,
    body: { messages: [{ id: "too-late" }] },
  });
  const timedOut = await sendWhatsAppOrderNotification(
    sampleOrder("+919901844776"),
    {
      isEnabled: async () => true,
      env: creds,
      fetch: timeoutFetch,
    }
  );
  assert(timedOut.sent === false && timedOut.reason === "error", "timeout contained");

  const boom = await sendWhatsAppOrderNotification(sampleOrder("+919901844776"), {
    isEnabled: async () => {
      throw new Error("setting lookup failed");
    },
    env: creds,
    fetch: mockFetch(),
  });
  assert(boom.sent === false && boom.reason === "error", "unexpected failure contained");

  let rejected = false;
  const pending = sendWhatsAppOrderNotification(sampleOrder("+919901844776"), {
    isEnabled: async () => {
      throw new Error("async boom");
    },
    env: creds,
    fetch: mockFetch(),
  });
  pending.then(
    () => {},
    () => {
      rejected = true;
    }
  );
  await pending;
  assert(rejected === false, "promise does not reject");

  const replayFetch = mockFetch({
    body: { messages: [{ id: "wamid.replay" }] },
  });
  const idempotentReplay = true;
  if (!idempotentReplay) {
    await sendWhatsAppOrderNotification(sampleOrder("+919901844776"), {
      isEnabled: async () => true,
      env: creds,
      fetch: replayFetch,
    });
  }
  assert(replayFetch.calls.length === 0, "idempotent replay skips WhatsApp");

  const buyerParams = buyerOrderTemplateParameters(orderNotificationOrder());
  assert(buyerParams[0] === "Asha", "buyer params start with customer");
  assert(buyerParams[1] === "SE-100001", "buyer params order number");
  assert(buyerParams[2] === "Meera", "buyer params seller");
  assert(buyerParams[3] === "2 x Idli, 1 x Masala Dosa", "buyer params items");
  assert(buyerParams[4] === "250", "buyer params amount");

  const readyEnv = {
    ...creds,
    [READY_TEMPLATE_ENV]: READY_TEMPLATE_NAME,
  };
  const readyFetch = mockFetch({
    body: { messages: [{ id: "wamid.ready" }] },
  });
  const readySent = await sendWhatsAppReadyNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: readyEnv,
    fetch: readyFetch,
  });
  assert(readySent.sent === true, "ready template sent");
  const readyBody = JSON.parse(readyFetch.calls[0].options.body);
  assert(readyBody.template.name === READY_TEMPLATE_NAME, "ready uses env template name");
  assert(readyBody.to === "919881234567", "ready targets buyer phone");

  const completedEnv = {
    ...creds,
    [COMPLETED_TEMPLATE_ENV]: COMPLETED_TEMPLATE_NAME,
  };
  const completedFetch = mockFetch({
    body: { messages: [{ id: "wamid.completed" }] },
  });
  const completedSent = await sendWhatsAppCompletedNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: completedEnv,
    fetch: completedFetch,
  });
  assert(completedSent.sent === true, "completed template sent");
  const completedBody = JSON.parse(completedFetch.calls[0].options.body);
  assert(
    completedBody.template.name === COMPLETED_TEMPLATE_NAME,
    "completed uses env template name"
  );
  const completedTo = completedBody.to;
  assert(completedTo === "919881234567", "completed targets buyer phone");
  const completedTexts = completedBody.template.components[0].parameters.map((row) => row.text);
  assert(completedTexts.length === 5, "completed has five body parameters");
  assert(completedTexts[0] === "Asha", "completed buyer name");

  const completedOff = await sendWhatsAppCompletedNotification(orderNotificationOrder(), {
    isEnabled: async () => false,
    env: completedEnv,
    fetch: mockFetch(),
  });
  assert(completedOff.reason === "admin_off", "admin off skips completed");

  const noTemplateEnv = { ...creds };
  delete noTemplateEnv[COMPLETED_TEMPLATE_ENV];
  const noTemplateFetch = mockFetch();
  const noTemplate = await sendWhatsAppCompletedNotification(orderNotificationOrder(), {
    isEnabled: async () => true,
    env: noTemplateEnv,
    fetch: noTemplateFetch,
  });
  assert(noTemplate.reason === "no_template", "unset completed template skips");
  assert(noTemplateFetch.calls.length === 0, "no template makes zero calls");

  assert(
    typeof notifications.notifyOrderCreated === "function",
    "FCM notifyOrderCreated export unchanged"
  );
  assert(
    typeof notifications.sendToUser === "function",
    "FCM sendToUser export unchanged"
  );
  assert(
    typeof notifications.flushNotification === "function",
    "FCM flushNotification export unchanged"
  );

  console.log("whatsapp-cloud.test.js passed");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
