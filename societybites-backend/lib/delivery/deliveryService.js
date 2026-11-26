const crypto = require("crypto");
const prisma = require("../prisma");
const logger = require("../logger");
const {
  PROROUTING,
  getDeliveryProvider,
  getDeliveryAllowlist,
  toProroutingPhone,
} = require("./deliverySetting");
const { evaluatePartnerDelivery, isPartnerDeliveryOrder } = require("./eligibility");
const {
  createOrder,
  estimate,
  updateOrder,
  cancelOrder,
  getStatus,
  proroutingConfig,
  isProroutingConfigured,
  logProroutingError,
} = require("./proroutingClient");
const { applyWebhookToTask, partnerSearchAction } = require("./webhookStatus");
const {
  computeOrderTotal,
  couponDiscountFromOrder,
  assertCanCompleteOrder,
} = require("../delayedDeliveryCharge");
const { notifyStatusChange, flushNotification } = require("../../utils/notifications");
const { dispatchWhatsAppStatusNotification } = require("../whatsappCloud");

function webhookTokensEqual(provided, expected) {
  const left = Buffer.from(String(provided || ""), "utf8");
  const right = Buffer.from(String(expected || ""), "utf8");
  if (!right.length || left.length !== right.length) return false;
  return crypto.timingSafeEqual(left, right);
}

function sellerFromOrder(order) {
  const listing =
    order && order.items && order.items[0] && order.items[0].listing;
  return (listing && listing.seller) || null;
}

function pickupSocietyFromOrder(order) {
  const seller = sellerFromOrder(order);
  return (seller && seller.society) || null;
}

function dropSocietyFromOrder(order) {
  return (order && order.buyer && order.buyer.society) || order.society || null;
}

function lineAddress(society, flat, name) {
  const parts = [
    name,
    flat && flat.block ? `Block ${flat.block}` : null,
    flat && flat.flatNumber ? `Flat ${flat.flatNumber}` : null,
    society && society.address,
    society && society.name,
  ].filter(Boolean);
  const line1 = parts[0] || (society && society.name) || "Address";
  const line2 = parts.slice(1).join(", ") || (society && society.city) || "";
  return { line1, line2 };
}

async function previewPartnerDeliveryForListing({
  listingId,
  buyerId,
  fulfilmentMethod,
  paymentMethod,
  env = process.env,
} = {}) {
  try {
    const [listing, buyer, provider, allowlist] = await Promise.all([
      prisma.listing.findUnique({
        where: { id: String(listingId || "") },
        include: { seller: { include: { society: true } } },
      }),
      prisma.user.findUnique({
        where: { id: String(buyerId || "") },
        include: { society: true },
      }),
      getDeliveryProvider(),
      getDeliveryAllowlist(),
    ]);
    if (!listing || !listing.seller || !buyer) {
      return { eligible: false };
    }
    const pickup = listing.seller.society;
    const drop = buyer.society;
    const result = evaluatePartnerDelivery({
      provider,
      allowlist,
      buyerPhone: buyer.phone,
      sellerPhone: listing.seller.phone,
      orderType: "regular",
      isCrossSociety: Boolean(
        pickup && drop && pickup.id && drop.id && pickup.id !== drop.id
      ),
      fulfilmentMethod,
      paymentMethod,
      pickupSociety: pickup,
      dropSociety: drop,
      env,
    });
    return { eligible: Boolean(result.useProrouting) };
  } catch (error) {
    logProroutingError("preview", error);
    return { eligible: false };
  }
}

async function resolveEligibilityForOrder(order, env = process.env) {
  const [provider, allowlist] = await Promise.all([
    getDeliveryProvider(),
    getDeliveryAllowlist(),
  ]);
  const seller = sellerFromOrder(order);
  const buyer = order && order.buyer;
  return evaluatePartnerDelivery({
    provider,
    allowlist,
    buyerPhone: buyer && buyer.phone,
    sellerPhone: seller && seller.phone,
    orderType: order && order.type,
    isCrossSociety: Boolean(
      seller &&
        seller.societyId &&
        order.societyId &&
        seller.societyId !== order.societyId
    ) ||
      Boolean(
        order.items &&
          order.items[0] &&
          order.items[0].listing &&
          order.items[0].listing.societyId &&
          order.societyId &&
          order.items[0].listing.societyId !== order.societyId
      ),
    fulfilmentMethod: order && order.fulfilmentMethod,
    paymentMethod: order && order.paymentMethod,
    pickupSociety: pickupSocietyFromOrder(order),
    dropSociety: dropSocietyFromOrder(order),
    env,
  });
}

function serializeDelivery(task, options = {}) {
  if (!task) return null;
  const viewerUserId = options.viewerUserId || null;
  const isBuyer = Boolean(viewerUserId && options.buyerId && viewerUserId === options.buyerId);
  const isSeller = Boolean(
    viewerUserId && options.sellerId && viewerUserId === options.sellerId
  );
  return {
    provider: task.provider,
    state: task.state,
    riderName: task.riderName || null,
    riderPhone: task.riderPhone || null,
    trackingUrl: task.trackingUrl || null,
    pickupOtp: isSeller ? task.pickupOtp || null : null,
    dropOtp: isBuyer ? task.dropOtp || null : null,
    quotedFare:
      isSeller && task.quotedFare != null ? Number(task.quotedFare) : null,
    billedFare:
      isSeller && task.billedFare != null ? Number(task.billedFare) : null,
    lspName: task.lspName || null,
    lastError: isSeller ? task.lastError || null : null,
  };
}

function firstFinitePrice(...values) {
  for (const value of values) {
    if (value == null || value === "") continue;
    const n = Number(value);
    if (Number.isFinite(n) && n >= 0) return n;
  }
  return null;
}

function parseEstimateQuote(json) {
  if (!json || typeof json !== "object") return null;
  if (json.status === 0) return null;
  const root =
    (json.estimate && typeof json.estimate === "object" && json.estimate) ||
    (json.order && typeof json.order === "object" && json.order) ||
    (json.data && typeof json.data === "object" && json.data) ||
    json;
  const price = firstFinitePrice(
    root.price,
    root.estimated_price,
    root.estimatedPrice,
    root.total_price,
    root.totalPrice,
    root.amount,
    json.price,
    json.estimated_price
  );
  if (price == null) return null;
  const estimateId =
    root.id ||
    root.estimate_id ||
    root.estimateId ||
    json.estimate_id ||
    json.estimateId ||
    null;
  return {
    price,
    estimateId: estimateId ? String(estimateId) : null,
  };
}

function estimateIdFromTask(task) {
  if (!task || !task.lastPayload) return null;
  try {
    const parsed = JSON.parse(task.lastPayload);
    if (!parsed || typeof parsed !== "object") return null;
    return (
      parsed.estimateId ||
      parsed.estimate_id ||
      (parsed.estimate && parsed.estimate.id) ||
      null
    );
  } catch (_err) {
    return null;
  }
}

async function quotePartnerDelivery(order) {
  const body = buildCreatePayload(order, {
    readyToShip: false,
    callbackUrl: "",
  }).body;
  delete body.callback_url;
  delete body.select_criteria;
  const response = await estimate(body);
  const quote = parseEstimateQuote(response);
  if (!quote) {
    const err = new Error("Prorouting estimate missing price");
    err.statusCode = 502;
    throw err;
  }
  return { ...quote, raw: response };
}

async function lockPartnerDeliveryIfEligible(order) {
  try {
    const result = await resolveEligibilityForOrder(order);
    if (!result.useProrouting) {
      logger.info(
        "delivery",
        `lock skipped for ${order.orderNumber || order.id}: ${(result.reasons || []).join(",") || "unknown"}`
      );
      return order;
    }
    let quote;
    try {
      quote = await quotePartnerDelivery(order);
    } catch (error) {
      logger.info(
        "delivery",
        `lock skipped for ${order.orderNumber || order.id}: estimate_failed`
      );
      logProroutingError("estimate", error);
      return order;
    }
    const nextTotal = computeOrderTotal({
      subtotal: order.subtotal,
      communityFee: order.communityFee,
      deliveryCharge: quote.price,
      couponDiscount: couponDiscountFromOrder(order),
    });
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: {
        deliveryProvider: PROROUTING,
        deliveryCharge: quote.price,
        total: nextTotal,
      },
    });
    const deliveryTask = await prisma.deliveryTask.upsert({
      where: { orderId: order.id },
      update: {
        provider: PROROUTING,
        state: "quoted",
        quotedFare: quote.price,
        lastError: null,
        lastPayload: JSON.stringify({
          estimateId: quote.estimateId,
          quotedFare: quote.price,
          estimate: quote.raw,
        }).slice(0, 8000),
      },
      create: {
        orderId: order.id,
        provider: PROROUTING,
        state: "quoted",
        quotedFare: quote.price,
        lastPayload: JSON.stringify({
          estimateId: quote.estimateId,
          quotedFare: quote.price,
          estimate: quote.raw,
        }).slice(0, 8000),
      },
    });
    return {
      ...order,
      ...updated,
      deliveryProvider: PROROUTING,
      deliveryCharge: quote.price,
      total: nextTotal,
      deliveryTask,
    };
  } catch (error) {
    logger.error("delivery", `lock skipped: ${error.message}`);
    return order;
  }
}

function buildCreatePayload(order, { readyToShip, callbackUrl, estimateId, pickupOtp, dropOtp }) {
  const seller = sellerFromOrder(order);
  const buyer = order.buyer || {};
  const pickupSociety = pickupSocietyFromOrder(order);
  const dropSociety = dropSocietyFromOrder(order);
  const pickupFlat = seller && seller.flat;
  const dropFlat = buyer.flat;
  const pickupAddr = lineAddress(
    pickupSociety,
    pickupFlat,
    (seller && seller.name) || pickupSociety.name
  );
  const dropAddr = lineAddress(
    dropSociety,
    dropFlat,
    buyer.name || dropSociety.name
  );
  const nextPickupOtp =
    pickupOtp || String(Math.floor(1000 + Math.random() * 9000));
  const nextDropOtp = dropOtp || String(Math.floor(1000 + Math.random() * 9000));
  const items = (order.items || []).map((item) => ({
    name: (item.listing && item.listing.name) || "Item",
    qty: item.quantity || 1,
    price: item.unitPrice || 0,
  }));
  return {
    pickupOtp: nextPickupOtp,
    dropOtp: nextDropOtp,
    body: {
      client_order_id: order.id,
      seller_order_id: order.orderNumber,
      retail_order_id: order.orderNumber,
      pickup: {
        lat: pickupSociety.latitude,
        lng: pickupSociety.longitude,
        address: {
          name: (seller && seller.name) || pickupSociety.name,
          line1: pickupAddr.line1,
          line2: pickupAddr.line2,
          city: pickupSociety.city,
          state: pickupSociety.state || "Karnataka",
        },
        pincode: String(pickupSociety.pincode),
        phone: toProroutingPhone(seller && seller.phone),
        otp: nextPickupOtp,
      },
      drop: {
        lat: dropSociety.latitude,
        lng: dropSociety.longitude,
        address: {
          name: buyer.name || dropSociety.name,
          line1: dropAddr.line1,
          line2: dropAddr.line2,
          city: dropSociety.city,
          state: dropSociety.state || "Karnataka",
        },
        pincode: String(dropSociety.pincode),
        phone: toProroutingPhone(buyer.phone),
        otp: nextDropOtp,
      },
      ...(callbackUrl ? { callback_url: callbackUrl } : {}),
      city: String(
        (pickupSociety && pickupSociety.city) ||
          (dropSociety && dropSociety.city) ||
          ""
      ).trim(),
      order_category: "F&B",
      search_category: "Immediate Delivery",
      ready_to_ship: readyToShip ? "yes" : "no",
      rto_required: false,
      order_amount: Number(order.subtotal || 0),
      cod_amount: 0,
      order_items: items,
      select_criteria: estimateId
        ? { mode: "estimated_price", estimate_id: estimateId }
        : { mode: "fastest_agent" },
    },
  };
}

function publicCallbackUrl(req) {
  const token = proroutingConfig().webhookToken;
  if (!token) return "";
  const configured = String(process.env.PROROUTING_CALLBACK_BASE_URL || "")
    .trim()
    .replace(/\/+$/, "");
  if (configured) {
    return `${configured}/webhooks/prorouting/${encodeURIComponent(token)}`;
  }
  const proto = req.get("x-forwarded-proto") || req.protocol || "https";
  const host = req.get("x-forwarded-host") || req.get("host");
  if (!host) return "";
  return `${proto}://${host}/webhooks/prorouting/${encodeURIComponent(token)}`;
}

async function bookOnReady(order, req) {
  if (!isPartnerDeliveryOrder(order)) return order;
  try {
    const callbackUrl = publicCallbackUrl(req || { get: () => null, protocol: "https" });
    let task = await prisma.deliveryTask.findUnique({
      where: { orderId: order.id },
    });
    if (!task) {
      task = await prisma.deliveryTask.create({
        data: {
          orderId: order.id,
          provider: PROROUTING,
          state: "quoted",
        },
      });
    }
    if (task.externalId) {
      await updateOrder({
        order: {
          id: task.externalId,
          pickup_code: task.pickupOtp || order.orderNumber,
          drop_code: task.dropOtp || undefined,
          order_ready: true,
        },
      });
      const saved = await prisma.deliveryTask.update({
        where: { id: task.id },
        data: { state: task.state === "quoted" ? "booked" : task.state },
      });
      return { ...order, deliveryTask: saved };
    }
    const estimateId = estimateIdFromTask(task);
    const built = buildCreatePayload(order, {
      readyToShip: true,
      callbackUrl,
      estimateId,
    });
    let response;
    try {
      response = await createOrder(built.body);
    } catch (error) {
      if (!estimateId) throw error;
      logProroutingError("bookOnReady-estimate", error);
      built.body.select_criteria = { mode: "fastest_agent" };
      response = await createOrder(built.body);
    }
    const externalId =
      (response && response.order && (response.order.id || response.order.order_id)) ||
      (response && response.id) ||
      null;
    const saved = await prisma.deliveryTask.update({
      where: { id: task.id },
      data: {
        state: "booked",
        externalId: externalId ? String(externalId) : null,
        pickupOtp: built.pickupOtp,
        dropOtp: built.dropOtp,
        bookedAt: task.bookedAt || new Date(),
        retryCount: task.retryCount || 0,
        lastError: null,
        lastPayload: JSON.stringify(response || {}),
      },
    });
    return { ...order, deliveryTask: saved };
  } catch (error) {
    logProroutingError("bookOnReady", error);
    try {
      await prisma.deliveryTask.updateMany({
        where: { orderId: order.id },
        data: {
          state: "failed",
          lastError: String(error.message || "book failed").slice(0, 500),
        },
      });
    } catch (_err) {
      /* ignore */
    }
    let failedTask = order.deliveryTask || null;
    try {
      failedTask = await prisma.deliveryTask.findUnique({
        where: { orderId: order.id },
      });
    } catch (_err) {
      /* ignore */
    }
    return { ...order, deliveryTask: failedTask || order.deliveryTask };
  }
}

async function cancelPartnerDelivery(order) {
  if (!isPartnerDeliveryOrder(order)) return;
  try {
    const task = await prisma.deliveryTask.findUnique({
      where: { orderId: order.id },
    });
    if (!task || !task.externalId) return;
    await cancelOrder({
      order: {
        id: task.externalId,
        cancellation_reason_id: "005",
        cancellation_reason_text: "Order cancelled on SocietyEats",
      },
    });
  } catch (error) {
    logProroutingError("cancel", error);
  }
}

async function applyProroutingWebhook(payload) {
  const remote = (payload && payload.order) || payload || {};
  const clientOrderId = remote.client_order_id || remote.clientOrderId;
  const externalId = remote.id;
  let task = null;
  if (clientOrderId) {
    task = await prisma.deliveryTask.findUnique({
      where: { orderId: String(clientOrderId) },
    });
  }
  if (!task && externalId) {
    task = await prisma.deliveryTask.findFirst({
      where: { externalId: String(externalId) },
    });
  }
  if (!task) {
    return { ok: true, ignored: true };
  }
  let source = remote;
  if (task.externalId && isProroutingConfigured()) {
    try {
      const live = await getStatus({ order: { id: task.externalId } });
      if (live && live.order) source = live.order;
    } catch (error) {
      logProroutingError("webhook-status", error);
    }
  }
  const applied = applyWebhookToTask(task, { order: source });
  if (applied.ignored) return { ok: true, ignored: true };
  const saved = await persistAppliedTask(task, applied);
  let graph = await prisma.order.findUnique({
    where: { id: task.orderId },
    include: completeOrderInclude,
  });
  if (graph) {
    graph = await maybeAdvanceStuckPartnerSearch({
      ...graph,
      deliveryTask: saved,
    });
  }
  await completePartnerOrderIfDelivered(task.orderId, applied.task.state);
  return { ok: true, ignored: false, orderId: task.orderId };
}

const LIVE_TERMINAL = new Set([
  "delivered",
  "cancelled",
  "failed",
  "rto",
  "seller_fallback",
]);
const partnerAdvanceLocks = new Set();

function partnerSearchTimings(env = process.env) {
  const retryMin = Number(env.PARTNER_SEARCH_RETRY_MINUTES);
  const fallbackMin = Number(env.PARTNER_SEARCH_FALLBACK_MINUTES);
  return {
    retryAfterMs: (Number.isFinite(retryMin) && retryMin > 0 ? retryMin : 15) * 60 * 1000,
    fallbackAfterMs:
      (Number.isFinite(fallbackMin) && fallbackMin > 0 ? fallbackMin : 60) * 60 * 1000,
  };
}

async function orderGraphForPartnerBook(order) {
  if (order && order.buyer && order.items && order.items[0] && order.items[0].listing) {
    return order;
  }
  return prisma.order.findUnique({
    where: { id: order.id },
    include: completeOrderInclude,
  });
}

async function retryPartnerBook(order, task) {
  const graph = await orderGraphForPartnerBook(order);
  if (!graph) return;
  try {
    if (task.externalId) {
      try {
        await cancelOrder({
          order: {
            id: task.externalId,
            cancellation_reason_id: "005",
            cancellation_reason_text: "No rider assigned; retrying search",
          },
        });
      } catch (error) {
        logProroutingError("retry-cancel", error);
      }
    }
    const callbackUrl = publicCallbackUrl({ get: () => null, protocol: "https" });
    const estimateId = estimateIdFromTask(task);
    const built = buildCreatePayload(graph, {
      readyToShip: true,
      callbackUrl,
      estimateId,
      pickupOtp: task.pickupOtp,
      dropOtp: task.dropOtp,
    });
    let response;
    try {
      response = await createOrder(built.body);
    } catch (error) {
      if (!estimateId) throw error;
      built.body.select_criteria = { mode: "fastest_agent" };
      response = await createOrder(built.body);
    }
    const externalId =
      (response && response.order && (response.order.id || response.order.order_id)) ||
      (response && response.id) ||
      null;
    await prisma.deliveryTask.update({
      where: { id: task.id },
      data: {
        state: "booked",
        externalId: externalId ? String(externalId) : null,
        pickupOtp: built.pickupOtp,
        dropOtp: built.dropOtp,
        riderName: null,
        riderPhone: null,
        lspName: null,
        trackingUrl: null,
        retryCount: 1,
        lastError: null,
        lastPayload: JSON.stringify(response || {}).slice(0, 8000),
      },
    });
    logger.info(
      "delivery",
      `${graph.orderNumber || graph.id} partner search retried`
    );
  } catch (error) {
    logProroutingError("retry-book", error);
    try {
      await prisma.deliveryTask.update({
        where: { id: task.id },
        data: {
          state: "failed",
          lastError: String(error.message || "retry failed").slice(0, 500),
        },
      });
    } catch (_err) {
      /* ignore */
    }
  }
}

async function fallbackPartnerSearch(order, task) {
  if (task.externalId) {
    try {
      await cancelOrder({
        order: {
          id: task.externalId,
          cancellation_reason_id: "005",
          cancellation_reason_text: "No rider assigned; seller fallback",
        },
      });
    } catch (error) {
      logProroutingError("fallback-cancel", error);
    }
  }
  const saved = await prisma.deliveryTask.update({
    where: { id: task.id },
    data: {
      state: "seller_fallback",
      lastError: "No rider assigned in time",
    },
  });
  logger.info(
    "delivery",
    `${order.orderNumber || order.id} partner search fell back to seller`
  );
  return { ...order, deliveryTask: saved };
}

async function maybeAdvanceStuckPartnerSearch(order) {
  if (!order || !isPartnerDeliveryOrder(order)) return order;
  const task = order.deliveryTask;
  if (!task) return order;
  const action = partnerSearchAction(task, Date.now(), partnerSearchTimings());
  if (action === "none") return order;
  if (partnerAdvanceLocks.has(order.id)) {
    return order;
  }
  partnerAdvanceLocks.add(order.id);
  try {
    if (action === "fallback") {
      const next = await fallbackPartnerSearch(order, task);
      partnerAdvanceLocks.delete(order.id);
      return next;
    }
    const retrying = await prisma.deliveryTask.update({
      where: { id: task.id },
      data: { state: "retrying", lastError: null },
    });
    void retryPartnerBook(order, retrying).finally(() => {
      partnerAdvanceLocks.delete(order.id);
    });
    return { ...order, deliveryTask: retrying };
  } catch (error) {
    partnerAdvanceLocks.delete(order.id);
    logProroutingError("partner-search-advance", error);
    return order;
  }
}
const PARTNER_COMPLETE_FROM = new Set(["ready", "picked_up"]);
const PARTNER_SELLER_COMPLETE_STATES = new Set([
  "delivered",
  "cancelled",
  "failed",
  "rto",
  "seller_fallback",
]);

const completeOrderInclude = {
  deliveryTask: true,
  buyer: { include: { flat: true, society: true } },
  items: {
    include: {
      listing: {
        include: {
          seller: { include: { flat: true, society: true } },
        },
      },
    },
  },
};

function partnerTaskAllowsSellerComplete(taskState) {
  const state = String(taskState || "").trim().toLowerCase();
  if (!state) return true;
  return PARTNER_SELLER_COMPLETE_STATES.has(state);
}

function shouldAutoCompletePartnerOrder(order, deliveryState) {
  if (String(deliveryState || "").trim().toLowerCase() !== "delivered") {
    return false;
  }
  if (!order || !isPartnerDeliveryOrder(order)) return false;
  if (!PARTNER_COMPLETE_FROM.has(String(order.status || ""))) return false;
  try {
    assertCanCompleteOrder(order);
    return true;
  } catch {
    return false;
  }
}

async function persistAppliedTask(task, applied) {
  const data = {};
  for (const key of [
    "state",
    "externalId",
    "lspName",
    "riderName",
    "riderPhone",
    "trackingUrl",
    "billedFare",
    "lastPayload",
  ]) {
    if (applied.task[key] !== undefined) data[key] = applied.task[key];
  }
  if (!Object.keys(data).length) return task;
  return prisma.deliveryTask.update({
    where: { id: task.id },
    data,
  });
}

async function refreshPartnerLiveStatus(order) {
  try {
    if (!isPartnerDeliveryOrder(order)) return order;
    const current = await maybeAdvanceStuckPartnerSearch(order);
    const task = current.deliveryTask;
    if (!task || !task.externalId) return current;
    if (String(task.state || "") === "retrying") return current;
    if (LIVE_TERMINAL.has(String(task.state || ""))) {
      const completed = await completePartnerOrderIfDelivered(current, task.state);
      if (!completed) return current;
      return {
        ...current,
        status: completed.status,
        completedAt: completed.completedAt,
      };
    }
    const live = await getStatus({ order: { id: task.externalId } });
    const remote = (live && live.order) || live;
    if (!remote) return current;
    const applied = applyWebhookToTask(task, { order: remote });
    if (applied.ignored) return current;
    const saved = await persistAppliedTask(task, applied);
    const completed = await completePartnerOrderIfDelivered(
      { ...current, deliveryTask: saved },
      saved.state
    );
    return {
      ...current,
      deliveryTask: saved,
      ...(completed
        ? { status: completed.status, completedAt: completed.completedAt }
        : {}),
    };
  } catch (error) {
    logProroutingError("live-status", error);
    return order;
  }
}

async function completePartnerOrderIfDelivered(orderOrId, deliveryState) {
  if (String(deliveryState || "").trim().toLowerCase() !== "delivered") {
    return null;
  }
  try {
    const order =
      orderOrId && typeof orderOrId === "object"
        ? orderOrId
        : await prisma.order.findUnique({
            where: { id: String(orderOrId) },
            include: completeOrderInclude,
          });
    if (!shouldAutoCompletePartnerOrder(order, deliveryState)) return null;
    const now = new Date();
    const result = await prisma.order.updateMany({
      where: { id: order.id, status: order.status },
      data: { status: "completed", completedAt: now },
    });
    if (result.count === 0) return null;
    const updated = { ...order, status: "completed", completedAt: now };
    logger.info(
      "order",
      `${order.orderNumber || order.id} → completed (partner delivered)`
    );
    void flushNotification(notifyStatusChange(updated, "completed"));
    dispatchWhatsAppStatusNotification(updated, "completed");
    return updated;
  } catch (error) {
    logProroutingError("complete-on-delivered", error);
    return null;
  }
}

async function refreshPartnerLiveStatusMany(orders) {
  if (!Array.isArray(orders) || orders.length === 0) return orders || [];
  const out = [];
  for (const order of orders) {
    out.push(await refreshPartnerLiveStatus(order));
  }
  return out;
}

module.exports = {
  webhookTokensEqual,
  previewPartnerDeliveryForListing,
  resolveEligibilityForOrder,
  serializeDelivery,
  parseEstimateQuote,
  estimateIdFromTask,
  quotePartnerDelivery,
  lockPartnerDeliveryIfEligible,
  bookOnReady,
  cancelPartnerDelivery,
  applyProroutingWebhook,
  refreshPartnerLiveStatus,
  refreshPartnerLiveStatusMany,
  completePartnerOrderIfDelivered,
  shouldAutoCompletePartnerOrder,
  partnerTaskAllowsSellerComplete,
  partnerSearchTimings,
  isPartnerDeliveryOrder,
};
