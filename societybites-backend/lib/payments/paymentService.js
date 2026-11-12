const prisma = require("../prisma");
const { upiPayableAmountForOrder } = require("../delayedDeliveryCharge");
const { CASHFREE, DIRECT_UPI, httpError } = require("./providers");
const { getPaymentProvider } = require("./paymentSetting");
const { sellerShareAmount, isEligibleBalanceError } = require("./sellerShare");
const {
  cashfreeConfig,
  cashfreeReturnUrl,
  createCashfreeUpiSession,
  upsertCashfreeVendor,
  fetchCashfreeVendor,
  splitCashfreeOrder,
} = require("./cashfreeClient");

const checkoutInclude = {
  buyer: { select: { id: true, phone: true, name: true } },
  items: {
    include: {
      listing: { select: { sellerId: true } },
    },
  },
};

const PAN_PATTERN = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
const IFSC_PATTERN = /^[A-Z]{4}0[A-Z0-9]{6}$/;

function sellerIdFromOrder(order) {
  const item = (order.items || [])[0];
  return item && item.listing && item.listing.sellerId;
}

function sessionFromOrder(order) {
  return {
    paymentProvider: order.paymentProvider || DIRECT_UPI,
    paymentStatus: order.paymentStatus || "pending",
    orderId: order.orderNumber,
    amount: order.gatewayAmount != null ? order.gatewayAmount : upiPayableAmountForOrder(order),
    gatewayUpiLink: order.gatewayUpiLink || null,
    gatewayQrPayload: order.gatewayQrPayload || null,
    splitStatus: order.splitStatus || null,
  };
}

async function loadCheckoutOrder(orderId) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: checkoutInclude,
  });
  if (!order) throw httpError(404, "Order not found");
  return order;
}

function assertBuyer(order, userId) {
  if (order.buyerId !== userId) {
    throw httpError(403, "Only the buyer can start payment");
  }
}

async function refreshCashfreeSession(order, returnOrigin) {
  const amount =
    order.gatewayAmount != null
      ? Number(order.gatewayAmount)
      : upiPayableAmountForOrder(order);
  const session = await createCashfreeUpiSession({
    order,
    amount,
    config: cashfreeConfig(),
    returnUrl: cashfreeReturnUrl({ origin: returnOrigin, orderId: order.id }),
  });
  const updated = await prisma.order.update({
    where: { id: order.id },
    data: {
      paymentProvider: CASHFREE,
      gatewayAmount: amount,
      gatewayUpiLink: session.gatewayUpiLink,
      gatewayQrPayload: session.gatewayQrPayload,
      gatewayPaymentId: session.gatewayPaymentId
        ? String(session.gatewayPaymentId)
        : order.gatewayPaymentId,
      paymentStatus: order.paymentStatus === "failed" ? "pending" : order.paymentStatus,
    },
    include: checkoutInclude,
  });
  return sessionFromOrder(updated);
}

async function beginCheckout({ orderId, userId, returnOrigin }) {
  const order = await loadCheckoutOrder(orderId);
  assertBuyer(order, userId);

  if (order.paymentMethod !== "upi") {
    return sessionFromOrder({ ...order, paymentProvider: DIRECT_UPI });
  }

  if (order.paymentStatus === "paid" || order.paymentStatus === "seller_confirmed") {
    return sessionFromOrder(order);
  }

  if (!["accepted", "preparing", "ready"].includes(order.status)) {
    throw httpError(400, "Order must be accepted before payment");
  }

  if (order.paymentProvider === CASHFREE) {
    if (order.paymentStatus === "pending" || order.paymentStatus === "failed") {
      if (!order.gatewayUpiLink || order.paymentStatus === "failed") {
        return refreshCashfreeSession(order, returnOrigin);
      }
    }
    return sessionFromOrder(order);
  }

  if (order.paymentProvider === DIRECT_UPI) {
    return sessionFromOrder(order);
  }

  const provider = await getPaymentProvider();
  if (provider !== CASHFREE) {
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { paymentProvider: DIRECT_UPI },
    });
    return sessionFromOrder({ ...order, ...updated });
  }

  const amount = upiPayableAmountForOrder(order);
  if (!(amount > 0)) {
    throw httpError(400, "This order has no UPI amount to collect");
  }
  const session = await createCashfreeUpiSession({
    order,
    amount,
    config: cashfreeConfig(),
    returnUrl: cashfreeReturnUrl({ origin: returnOrigin, orderId: order.id }),
  });
  const updated = await prisma.order.update({
    where: { id: order.id },
    data: {
      paymentProvider: CASHFREE,
      gatewayAmount: amount,
      gatewayUpiLink: session.gatewayUpiLink,
      gatewayQrPayload: session.gatewayQrPayload,
      gatewayPaymentId: session.gatewayPaymentId
        ? String(session.gatewayPaymentId)
        : null,
      splitStatus: "pending",
    },
    include: checkoutInclude,
  });
  return sessionFromOrder(updated);
}

async function attemptSplit(order) {
  if (order.paymentProvider !== CASHFREE) return order;
  if (order.splitStatus === "created" || order.splitStatus === "not_required") {
    return order;
  }
  const sellerId = sellerIdFromOrder(order);
  if (!sellerId) {
    return prisma.order.update({
      where: { id: order.id },
      data: { splitStatus: "pending", splitError: "Seller payout profile is missing" },
      include: checkoutInclude,
    });
  }
  const seller = await prisma.user.findUnique({
    where: { id: sellerId },
    include: { payoutProfile: true },
  });
  const profile = seller && seller.payoutProfile;
  if (!profile || !profile.vendorId) {
    return prisma.order.update({
      where: { id: order.id },
      data: { splitStatus: "pending", splitError: "Seller payout profile is missing" },
      include: checkoutInclude,
    });
  }

  let vendorStatus = profile.vendorStatus;
  if (vendorStatus !== "ACTIVE") {
    try {
      const remote = await fetchCashfreeVendor({
        vendorId: profile.vendorId,
        config: cashfreeConfig(),
      });
      vendorStatus = (remote && remote.status) || vendorStatus;
      await prisma.sellerPayoutProfile.update({
        where: { userId: sellerId },
        data: { vendorStatus, vendorError: null },
      });
    } catch (error) {
      vendorStatus = profile.vendorStatus;
    }
  }
  if (vendorStatus !== "ACTIVE") {
    return prisma.order.update({
      where: { id: order.id },
      data: {
        splitStatus: "pending",
        splitError: "Seller vendor is not active yet",
      },
      include: checkoutInclude,
    });
  }

  const amount = sellerShareAmount(order);
  if (!(amount > 0)) {
    return prisma.order.update({
      where: { id: order.id },
      data: { splitStatus: "not_required", splitError: null },
      include: checkoutInclude,
    });
  }

  try {
    await splitCashfreeOrder({
      orderNumber: order.orderNumber,
      vendorId: profile.vendorId,
      amount,
      config: cashfreeConfig(),
    });
    return prisma.order.update({
      where: { id: order.id },
      data: { splitStatus: "created", splitError: null },
      include: checkoutInclude,
    });
  } catch (error) {
    return prisma.order.update({
      where: { id: order.id },
      data: {
        splitStatus: "failed",
        splitError: isEligibleBalanceError(error)
          ? error.message
          : error.message || "Split failed",
      },
      include: checkoutInclude,
    });
  }
}

function webhookOutcome(payload) {
  const type = String((payload && payload.type) || "");
  const payment = payload && payload.data && payload.data.payment;
  const status = String((payment && payment.payment_status) || "").toUpperCase();
  if (type === "PAYMENT_FAILED_WEBHOOK" || status === "FAILED" || status === "USER_DROPPED") {
    return "failed";
  }
  if (type === "PAYMENT_SUCCESS_WEBHOOK" || status === "SUCCESS") return "success";
  return "ignore";
}

async function applyCashfreeWebhook(payload) {
  const outcome = webhookOutcome(payload);
  if (outcome === "ignore") return { ignored: true };
  const orderNumber =
    payload &&
    payload.data &&
    payload.data.order &&
    payload.data.order.order_id;
  if (!orderNumber) return { ignored: true };
  const order = await prisma.order.findUnique({
    where: { orderNumber: String(orderNumber) },
    include: checkoutInclude,
  });
  if (!order || order.paymentProvider !== CASHFREE) return { ignored: true };

  const payment = payload.data.payment || {};
  if (outcome === "failed") {
    if (order.paymentStatus === "paid") return { order, ignored: true };
    const updated = await prisma.order.update({
      where: { id: order.id },
      data: { paymentStatus: "failed" },
      include: checkoutInclude,
    });
    return { order: updated, paidNow: false };
  }

  const gatewayPaymentId = payment.cf_payment_id
    ? String(payment.cf_payment_id)
    : order.gatewayPaymentId;
  const paidNow = order.paymentStatus !== "paid";
  let current = order;
  if (paidNow) {
    current = await prisma.order.update({
      where: { id: order.id },
      data: {
        paymentStatus: "paid",
        sellerConfirmedPaidAt: order.sellerConfirmedPaidAt || new Date(),
        gatewayPaymentId,
      },
      include: checkoutInclude,
    });
  }
  const split = await attemptSplit(current);
  return { order: split, paidNow };
}

function normalizePan(value) {
  return String(value || "").trim().toUpperCase();
}

async function savePayoutProfile({ user, body }) {
  if (!user || (user.role !== "seller" && user.role !== "super_admin")) {
    throw httpError(403, "Only a seller can save a payout profile");
  }
  const pan = normalizePan(body && body.pan);
  if (!PAN_PATTERN.test(pan)) {
    throw httpError(400, "Enter a valid PAN");
  }
  const settlementMode = String((body && body.settlementMode) || "").trim().toLowerCase();
  if (settlementMode !== "upi" && settlementMode !== "bank") {
    throw httpError(400, "settlementMode must be upi or bank");
  }
  const data = {
    pan,
    settlementMode,
    accountNumber: null,
    ifsc: null,
    accountHolder: null,
    vendorError: null,
  };
  if (settlementMode === "upi") {
    if (!user.upiId) {
      throw httpError(400, "Add a UPI ID before choosing UPI settlement");
    }
    data.accountHolder =
      (body.accountHolder && String(body.accountHolder).trim()) ||
      user.upiDisplayName ||
      user.name ||
      null;
  } else {
    const accountNumber = String((body && body.accountNumber) || "").replace(/\s/g, "");
    const ifsc = String((body && body.ifsc) || "").trim().toUpperCase();
    const accountHolder = String((body && body.accountHolder) || "").trim();
    if (!/^\d{9,18}$/.test(accountNumber)) {
      throw httpError(400, "Enter a valid bank account number");
    }
    if (!IFSC_PATTERN.test(ifsc)) {
      throw httpError(400, "Enter a valid IFSC");
    }
    if (!accountHolder) {
      throw httpError(400, "Enter the account holder name");
    }
    data.accountNumber = accountNumber;
    data.ifsc = ifsc;
    data.accountHolder = accountHolder;
  }

  const existing = await prisma.sellerPayoutProfile.findUnique({
    where: { userId: user.id },
  });
  const profile = existing
    ? await prisma.sellerPayoutProfile.update({
        where: { userId: user.id },
        data,
      })
    : await prisma.sellerPayoutProfile.create({
        data: { ...data, userId: user.id },
      });

  try {
    const remote = await upsertCashfreeVendor({
      user,
      profile,
      config: cashfreeConfig(),
    });
    return prisma.sellerPayoutProfile.update({
      where: { userId: user.id },
      data: {
        vendorId: remote.vendorId,
        vendorStatus: remote.vendorStatus,
        vendorError: null,
      },
    });
  } catch (error) {
    return prisma.sellerPayoutProfile.update({
      where: { userId: user.id },
      data: { vendorError: error.message || "Vendor registration failed" },
    });
  }
}

function publicPayoutProfile(profile, user) {
  if (!profile) {
    return {
      pan: null,
      settlementMode: null,
      accountHolder: null,
      accountNumber: null,
      ifsc: null,
      vendorStatus: null,
      vendorError: null,
      upiId: (user && user.upiId) || null,
    };
  }
  return {
    pan: profile.pan,
    settlementMode: profile.settlementMode,
    accountHolder: profile.accountHolder,
    accountNumber: profile.accountNumber,
    ifsc: profile.ifsc,
    vendorStatus: profile.vendorStatus,
    vendorError: profile.vendorError,
    upiId: (user && user.upiId) || null,
  };
}

module.exports = {
  beginCheckout,
  attemptSplit,
  applyCashfreeWebhook,
  webhookOutcome,
  savePayoutProfile,
  publicPayoutProfile,
  sellerIdFromOrder,
  sessionFromOrder,
};
