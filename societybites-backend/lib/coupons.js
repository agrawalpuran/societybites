const prisma = require("./prisma");

const REASONS = {
  INVALID_COUPON: "INVALID_COUPON",
  COUPON_EXPIRED: "COUPON_EXPIRED",
  COUPON_NOT_STARTED: "COUPON_NOT_STARTED",
  MINIMUM_ORDER_NOT_MET: "MINIMUM_ORDER_NOT_MET",
  USAGE_LIMIT_REACHED: "USAGE_LIMIT_REACHED",
  BUYER_USAGE_LIMIT_REACHED: "BUYER_USAGE_LIMIT_REACHED",
  NOT_ELIGIBLE: "NOT_ELIGIBLE",
  NOT_ELIGIBLE_SOCIETY: "NOT_ELIGIBLE_SOCIETY",
  NOT_ELIGIBLE_SELLER: "NOT_ELIGIBLE_SELLER",
  COUPON_PAUSED: "COUPON_PAUSED",
  COUPON_EXHAUSTED: "COUPON_EXHAUSTED",
  COUPON_ALREADY_APPLIED: "COUPON_ALREADY_APPLIED",
};

const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;
const ACTIVE_ORDER_STATUSES = ["APPLIED", "REDEEMED"];

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function money(value) {
  return Math.round(Number(value) * 100) / 100;
}

function formatRupee(value) {
  const amount = money(value);
  if (amount === Math.floor(amount)) return `₹${amount}`;
  return `₹${amount.toFixed(2)}`;
}

function normalizeCode(code) {
  return String(code || "").trim().toUpperCase();
}

function normalizeSubtotal(orderSubtotal) {
  const amount = Number(orderSubtotal);
  if (!Number.isFinite(amount) || amount < 0) {
    throw httpError(400, "orderSubtotal is invalid");
  }
  return money(amount);
}

function invalid(reason, extra = {}) {
  return { valid: false, reason, ...extra };
}

function istParts(date) {
  const shifted = new Date(date.getTime() + IST_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth(),
    day: shifted.getUTCDate(),
    weekday: shifted.getUTCDay(),
  };
}

function startOfIstDay(date) {
  const parts = istParts(date);
  return new Date(Date.UTC(parts.year, parts.month, parts.day) - IST_OFFSET_MS);
}

function startOfIstWeek(date) {
  const parts = istParts(date);
  const daysSinceMonday = (parts.weekday + 6) % 7;
  return new Date(startOfIstDay(date).getTime() - daysSinceMonday * 86400000);
}

function startOfIstMonth(date) {
  const parts = istParts(date);
  return new Date(Date.UTC(parts.year, parts.month, 1) - IST_OFFSET_MS);
}

function frequencyWindowStart(frequency, now) {
  if (frequency === "DAILY") return startOfIstDay(now);
  if (frequency === "WEEKLY") return startOfIstWeek(now);
  if (frequency === "MONTHLY") return startOfIstMonth(now);
  return null;
}

function discountFor(coupon, orderSubtotal) {
  let discount = 0;
  if (coupon.discountType === "PERCENTAGE") {
    discount = (orderSubtotal * Number(coupon.discountValue)) / 100;
    if (coupon.maximumDiscount != null) {
      discount = Math.min(discount, Number(coupon.maximumDiscount));
    }
  } else {
    discount = Number(coupon.discountValue);
    if (coupon.maximumDiscount != null) {
      discount = Math.min(discount, Number(coupon.maximumDiscount));
    }
  }
  discount = Math.min(Math.max(discount, 0), orderSubtotal);
  return money(discount);
}

function quoteFromDiscount(coupon, orderSubtotal, discountAmount) {
  return {
    valid: true,
    couponId: coupon.id,
    code: coupon.code,
    discountAmount,
    orderSubtotal,
    buyerPayable: money(orderSubtotal - discountAmount),
    sellerGrossAmount: orderSubtotal,
    societyEatsSubsidy: discountAmount,
  };
}

async function redeemedStats(db, couponId, userId) {
  const redeemed = await db.couponRedemption.findMany({
    where: { couponId, status: "REDEEMED" },
    select: { userId: true, discountAmount: true, redeemedAt: true, appliedAt: true },
  });
  const mine = userId ? redeemed.filter((row) => row.userId === userId) : [];
  const amountUsed = money(redeemed.reduce((sum, row) => sum + Number(row.discountAmount), 0));
  return { redeemed, mine, amountUsed, totalUsage: redeemed.length };
}

function buyerBlockedByFrequency(coupon, mine, now) {
  if (coupon.usageFrequency === "ONCE") {
    return mine.length >= 1;
  }
  const windowStart = frequencyWindowStart(coupon.usageFrequency, now);
  if (!windowStart) return false;
  return mine.some((row) => new Date(row.redeemedAt || row.appliedAt) >= windowStart);
}

function normalizeSellerId(raw) {
  const value = String(raw ?? "").trim();
  return value || null;
}

function sellerScopeMismatch(coupon, orderSellerId) {
  if (!coupon.sellerId) return false;
  const scoped = String(coupon.sellerId);
  const orderSeller = normalizeSellerId(orderSellerId);
  if (!orderSeller || orderSeller !== scoped) return true;
  return false;
}

async function societyScopeMismatch(db, coupon, userId) {
  const eligible =
    coupon.eligibleSocieties ||
    (await db.couponEligibleSociety.findMany({
      where: { couponId: coupon.id },
      select: { societyId: true },
    }));
  if (!eligible.length) return false;

  const user = await db.user.findUnique({
    where: { id: userId },
    select: { societyId: true },
  });
  const buyerSocietyId = user && user.societyId ? String(user.societyId) : null;
  if (!buyerSocietyId) return true;

  const allowed = new Set(eligible.map((row) => String(row.societyId)));
  return !allowed.has(buyerSocietyId);
}

async function validateCoupon({
  code,
  userId,
  orderSubtotal,
  sellerId = null,
  now = new Date(),
  db = prisma,
}) {
  if (!userId) return invalid(REASONS.INVALID_COUPON);
  const normalized = normalizeCode(code);
  if (!normalized) return invalid(REASONS.INVALID_COUPON);
  const subtotal = normalizeSubtotal(orderSubtotal);

  const coupon = await db.coupon.findUnique({
    where: { code: normalized },
    include: {
      eligibleSocieties: { select: { societyId: true } },
    },
  });
  if (!coupon || coupon.fundedBy !== "SOCIETYEATS") return invalid(REASONS.INVALID_COUPON);
  if (coupon.status === "PAUSED") return invalid(REASONS.COUPON_PAUSED);
  if (coupon.status === "EXHAUSTED") return invalid(REASONS.COUPON_EXHAUSTED);
  if (coupon.status === "EXPIRED") return invalid(REASONS.COUPON_EXPIRED);
  if (coupon.status !== "ACTIVE") return invalid(REASONS.INVALID_COUPON);
  if (now < new Date(coupon.validFrom)) return invalid(REASONS.COUPON_NOT_STARTED);
  if (now > new Date(coupon.validUntil)) return invalid(REASONS.COUPON_EXPIRED);
  if (subtotal < Number(coupon.minimumOrderValue || 0)) {
    const minimumOrderValue = money(Number(coupon.minimumOrderValue || 0));
    return invalid(REASONS.MINIMUM_ORDER_NOT_MET, {
      minimumOrderValue,
      orderSubtotal: subtotal,
    });
  }

  if (coupon.audienceType === "SELECTED_USERS") {
    const eligible = await db.couponEligibleUser.findUnique({
      where: { couponId_userId: { couponId: coupon.id, userId } },
    });
    if (!eligible) return invalid(REASONS.NOT_ELIGIBLE);
  }

  if (sellerScopeMismatch(coupon, sellerId)) {
    return invalid(REASONS.NOT_ELIGIBLE_SELLER);
  }

  if (await societyScopeMismatch(db, coupon, userId)) {
    return invalid(REASONS.NOT_ELIGIBLE_SOCIETY);
  }

  const stats = await redeemedStats(db, coupon.id, userId);
  if (coupon.totalUsageLimit != null && stats.totalUsage >= coupon.totalUsageLimit) {
    return invalid(REASONS.USAGE_LIMIT_REACHED);
  }
  if (coupon.usagePerBuyerLimit != null && stats.mine.length >= coupon.usagePerBuyerLimit) {
    return invalid(REASONS.BUYER_USAGE_LIMIT_REACHED);
  }
  if (buyerBlockedByFrequency(coupon, stats.mine, now)) {
    return invalid(REASONS.BUYER_USAGE_LIMIT_REACHED);
  }

  const discountAmount = discountFor(coupon, subtotal);
  if (
    coupon.campaignBudget != null &&
    stats.amountUsed + discountAmount > Number(coupon.campaignBudget) + 0.001
  ) {
    return invalid(REASONS.COUPON_EXHAUSTED);
  }

  return quoteFromDiscount(coupon, subtotal, discountAmount);
}

function couponErrorMessage(reason, context = {}) {
  if (reason === REASONS.MINIMUM_ORDER_NOT_MET && context.minimumOrderValue != null) {
    const minimum = money(context.minimumOrderValue);
    const current = context.orderSubtotal != null ? money(context.orderSubtotal) : null;
    if (current != null && current < minimum) {
      const shortfall = money(minimum - current);
      return `Minimum food order ${formatRupee(minimum)}. Add ${formatRupee(shortfall)} more to use this coupon`;
    }
    return `Minimum food order ${formatRupee(minimum)} required for this coupon`;
  }
  return (
    {
      INVALID_COUPON: "This coupon code is not valid",
      COUPON_EXPIRED: "This coupon has expired",
      COUPON_NOT_STARTED: "This coupon is not active yet",
      MINIMUM_ORDER_NOT_MET: "Your order does not meet the minimum amount for this coupon",
      USAGE_LIMIT_REACHED: "This coupon has reached its usage limit",
      BUYER_USAGE_LIMIT_REACHED: "You have already used this coupon",
      NOT_ELIGIBLE: "This coupon is not available for your account",
      NOT_ELIGIBLE_SOCIETY: "This coupon is not available in your society",
      NOT_ELIGIBLE_SELLER: "This coupon is not valid for this kitchen",
      COUPON_PAUSED: "This coupon is paused",
      COUPON_EXHAUSTED: "This coupon is no longer available",
      COUPON_ALREADY_APPLIED: "A coupon is already applied to this order",
    }[reason] || "This coupon could not be applied"
  );
}

async function attachCouponRedemption({
  code,
  userId,
  orderSubtotal,
  sellerId = null,
  orderId = null,
  now = new Date(),
  db,
  status = "APPLIED",
}) {
  if (orderId) {
    const existing = await db.couponRedemption.findFirst({
      where: { orderId, status: { in: ACTIVE_ORDER_STATUSES } },
    });
    if (existing) return invalid(REASONS.COUPON_ALREADY_APPLIED);
  }

  const normalized = normalizeCode(code);
  const coupon = await db.coupon.findUnique({ where: { code: normalized } });
  if (!coupon) return invalid(REASONS.INVALID_COUPON);
  await db.$queryRaw`SELECT "id" FROM "Coupon" WHERE "id" = ${coupon.id} FOR UPDATE`;

  const quote = await validateCoupon({
    code,
    userId,
    orderSubtotal,
    sellerId,
    now,
    db,
  });
  if (!quote.valid) return quote;

  await db.couponRedemption.create({
    data: {
      couponId: quote.couponId,
      userId,
      orderId,
      discountAmount: quote.discountAmount,
      status,
      appliedAt: now,
      redeemedAt: status === "REDEEMED" ? now : null,
    },
  });
  return quote;
}

async function applyCoupon({
  code,
  userId,
  orderSubtotal,
  sellerId = null,
  orderId = null,
  now = new Date(),
}) {
  try {
    const quote = await prisma.$transaction(async (tx) =>
      attachCouponRedemption({
        code,
        userId,
        orderSubtotal,
        sellerId,
        orderId,
        now,
        db: tx,
        status: "APPLIED",
      })
    );
    if (!quote.valid) return quote;
    return quote;
  } catch (err) {
    if (err.statusCode) return invalid(err.message);
    if (err.code === "P2002") return invalid(REASONS.COUPON_ALREADY_APPLIED);
    throw err;
  }
}

async function reverseCouponForOrder(orderId, db = prisma) {
  if (!orderId) return;
  await db.couponRedemption.updateMany({
    where: { orderId, status: { in: ACTIVE_ORDER_STATUSES } },
    data: { status: "REVERSED", reversedAt: new Date() },
  });
}

function usageSummary(coupon, redemptions) {
  const redeemed = redemptions.filter((row) => row.status === "REDEEMED");
  const amountUsed = money(redeemed.reduce((sum, row) => sum + Number(row.discountAmount), 0));
  const remainingBudget = coupon.campaignBudget == null ? null : money(Number(coupon.campaignBudget) - amountUsed);
  return {
    totalUsage: redeemed.length,
    appliedCount: redemptions.filter((row) => row.status === "APPLIED").length,
    reversedCount: redemptions.filter((row) => row.status === "REVERSED").length,
    usageLimit: coupon.totalUsageLimit,
    amountUsed,
    campaignBudget: coupon.campaignBudget,
    remainingBudget,
  };
}

function mapEligibleSocieties(coupon) {
  const rows = Array.isArray(coupon.eligibleSocieties) ? coupon.eligibleSocieties : [];
  return rows.map((row) => ({
    id: row.societyId,
    name: row.society && row.society.name ? row.society.name : null,
    city: row.society && row.society.city ? row.society.city : null,
  }));
}

function serializeCoupon(coupon, summary) {
  const eligibleSocieties = mapEligibleSocieties(coupon);
  return {
    id: coupon.id,
    code: coupon.code,
    name: coupon.name,
    description: coupon.description,
    discountType: coupon.discountType,
    discountValue: coupon.discountValue,
    maximumDiscount: coupon.maximumDiscount,
    minimumOrderValue: coupon.minimumOrderValue,
    validFrom: coupon.validFrom,
    validUntil: coupon.validUntil,
    totalUsageLimit: coupon.totalUsageLimit,
    usagePerBuyerLimit: coupon.usagePerBuyerLimit,
    usageFrequency: coupon.usageFrequency,
    campaignBudget: coupon.campaignBudget,
    audienceType: coupon.audienceType,
    status: coupon.status,
    fundedBy: coupon.fundedBy,
    sellerId: coupon.sellerId ?? null,
    sellerName: coupon.seller && coupon.seller.name ? coupon.seller.name : null,
    sellerPhone: coupon.seller && coupon.seller.phone ? coupon.seller.phone : null,
    eligibleSocietyIds: eligibleSocieties.map((row) => row.id),
    eligibleSocieties,
    createdAt: coupon.createdAt,
    updatedAt: coupon.updatedAt,
    ...summary,
  };
}

async function resolveCouponSellerId(raw, { partial = false } = {}) {
  if (raw === undefined && partial) return undefined;
  if (raw === null || raw === "" || raw === false) return null;
  const sellerId = normalizeSellerId(raw);
  if (!sellerId) return null;
  const user = await prisma.user.findUnique({
    where: { id: sellerId },
    select: { id: true, role: true },
  });
  if (!user) throw httpError(400, "Seller was not found");
  if (user.role !== "seller" && user.role !== "super_admin") {
    throw httpError(400, "Coupon seller must be a kitchen account");
  }
  return sellerId;
}

async function parseCouponWrite(body, { partial = false } = {}) {
  const source = body && typeof body === "object" ? body : {};
  const data = {};

  if (!partial || source.code != null) {
    const code = normalizeCode(source.code);
    if (!code || code.length > 40) throw httpError(400, "Coupon code is invalid");
    data.code = code;
  }
  if (!partial || source.name != null) {
    const name = String(source.name || "").trim();
    if (!name || name.length > 80) throw httpError(400, "Coupon name is required");
    data.name = name;
  }
  if (source.description != null) {
    const description = String(source.description).trim();
    data.description = description || null;
  }
  if (!partial || source.discountType != null || source.discountValue != null) {
    const discountType = String(source.discountType || "FIXED").trim().toUpperCase();
    if (discountType !== "FIXED" && discountType !== "PERCENTAGE") {
      throw httpError(400, "Discount type must be FIXED or PERCENTAGE");
    }
    const discountValue = Number(source.discountValue);
    if (!Number.isFinite(discountValue) || discountValue <= 0) {
      throw httpError(400, "Discount value must be greater than zero");
    }
    if (discountType === "PERCENTAGE" && discountValue > 100) {
      throw httpError(400, "Percentage discount cannot exceed 100");
    }
    data.discountType = discountType;
    data.discountValue =
      discountType === "PERCENTAGE" ? discountValue : money(discountValue);
  }
  if (source.maximumDiscount != null && source.maximumDiscount !== "") {
    const cap = Number(source.maximumDiscount);
    if (!Number.isFinite(cap) || cap <= 0) throw httpError(400, "Maximum discount is invalid");
    data.maximumDiscount = money(cap);
  }
  if (!partial || source.minimumOrderValue != null) {
    const minimum = source.minimumOrderValue == null ? 0 : Number(source.minimumOrderValue);
    if (!Number.isFinite(minimum) || minimum < 0) throw httpError(400, "Minimum order value is invalid");
    data.minimumOrderValue = money(minimum);
  }
  if (!partial || source.validFrom != null || source.validUntil != null) {
    const validFrom = new Date(source.validFrom);
    const validUntil = new Date(source.validUntil);
    if (Number.isNaN(validFrom.getTime()) || Number.isNaN(validUntil.getTime()) || validUntil <= validFrom) {
      throw httpError(400, "Coupon dates are invalid");
    }
    data.validFrom = validFrom;
    data.validUntil = validUntil;
  }
  if (source.totalUsageLimit != null && source.totalUsageLimit !== "") {
    const limit = Number(source.totalUsageLimit);
    if (!Number.isInteger(limit) || limit < 1) throw httpError(400, "Total usage limit is invalid");
    data.totalUsageLimit = limit;
  }
  if (source.usagePerBuyerLimit != null && source.usagePerBuyerLimit !== "") {
    const limit = Number(source.usagePerBuyerLimit);
    if (!Number.isInteger(limit) || limit < 1) throw httpError(400, "Buyer usage limit is invalid");
    data.usagePerBuyerLimit = limit;
  }
  if (source.usageFrequency != null && source.usageFrequency !== "") {
    const frequency = String(source.usageFrequency).trim().toUpperCase();
    if (!["ONCE", "DAILY", "WEEKLY", "MONTHLY", "CUSTOM"].includes(frequency)) {
      throw httpError(400, "Usage frequency is invalid");
    }
    data.usageFrequency = frequency;
  }
  if (source.campaignBudget != null && source.campaignBudget !== "") {
    const budget = Number(source.campaignBudget);
    if (!Number.isFinite(budget) || budget <= 0) throw httpError(400, "Campaign budget is invalid");
    data.campaignBudget = money(budget);
  }
  if (!partial || source.audienceType != null) {
    const audience = String(source.audienceType || "ALL").trim().toUpperCase();
    if (!["ALL", "SELECTED_USERS"].includes(audience)) throw httpError(400, "Audience is invalid");
    data.audienceType = audience;
  }
  if (source.sellerId !== undefined) {
    data.sellerId = await resolveCouponSellerId(source.sellerId, { partial });
  }
  if (source.status != null) {
    const status = String(source.status).trim().toUpperCase();
    if (!["DRAFT", "ACTIVE", "PAUSED"].includes(status)) {
      throw httpError(400, "Status must be DRAFT, ACTIVE, or PAUSED");
    }
    data.status = status;
  } else if (!partial) {
    data.status = "DRAFT";
  }
  data.fundedBy = "SOCIETYEATS";
  return data;
}

async function withSummary(coupon) {
  const redemptions = await prisma.couponRedemption.findMany({
    where: { couponId: coupon.id },
    select: { status: true, discountAmount: true },
  });
  return serializeCoupon(coupon, usageSummary(coupon, redemptions));
}

async function loadCouponRow(id) {
  return prisma.coupon.findUnique({
    where: { id },
    include: couponSellerInclude,
  });
}

async function createCoupon(body) {
  const source = body && typeof body === "object" ? body : {};
  const societyIds = source.societyIds;
  const data = await parseCouponWrite(source);
  try {
    const coupon = await prisma.coupon.create({ data });
    if (Array.isArray(societyIds) && societyIds.length) {
      await assignEligibleSocieties(coupon.id, societyIds, { skipReturn: true });
    }
    const full = await loadCouponRow(coupon.id);
    return withSummary(full || coupon);
  } catch (err) {
    if (err.code === "P2002") throw httpError(409, "Coupon code already exists");
    throw err;
  }
}

async function listCoupons() {
  const coupons = await prisma.coupon.findMany({
    orderBy: { createdAt: "desc" },
    include: couponSellerInclude,
  });
  return Promise.all(coupons.map(withSummary));
}

const couponSellerInclude = {
  seller: { select: { id: true, name: true, phone: true } },
  eligibleSocieties: {
    select: {
      societyId: true,
      society: { select: { id: true, name: true, city: true } },
    },
  },
};

async function getCoupon(id) {
  const coupon = await prisma.coupon.findUnique({
    where: { id },
    include: {
      eligibleUsers: { select: { userId: true } },
      ...couponSellerInclude,
    },
  });
  if (!coupon) throw httpError(404, "Coupon not found");
  const summary = await withSummary(coupon);
  return {
    ...summary,
    eligibleUserIds: coupon.eligibleUsers.map((row) => row.userId),
    eligibleSocietyIds: coupon.eligibleSocieties.map((row) => row.societyId),
  };
}

async function updateCoupon(id, body) {
  const existing = await prisma.coupon.findUnique({
    where: { id },
    include: { _count: { select: { redemptions: true } } },
  });
  if (!existing) throw httpError(404, "Coupon not found");
  const data = await parseCouponWrite(body, { partial: true });
  if (existing._count.redemptions > 0) {
    delete data.code;
    delete data.discountType;
    delete data.discountValue;
    delete data.fundedBy;
    delete data.sellerId;
  }
  const coupon = await prisma.coupon.update({ where: { id }, data });
  const full = await loadCouponRow(coupon.id);
  return withSummary(full || coupon);
}

async function setCouponStatus(id, status) {
  const coupon = await prisma.coupon.findUnique({ where: { id } });
  if (!coupon) throw httpError(404, "Coupon not found");
  if (status === "ACTIVE" && new Date() > new Date(coupon.validUntil)) {
    throw httpError(400, "Coupon has expired");
  }
  const updated = await prisma.coupon.update({ where: { id }, data: { status } });
  return withSummary(updated);
}

async function assignEligibleUsers(id, userIds) {
  const coupon = await prisma.coupon.findUnique({ where: { id } });
  if (!coupon) throw httpError(404, "Coupon not found");
  const ids = Array.isArray(userIds) ? [...new Set(userIds.map((value) => String(value).trim()).filter(Boolean))] : [];
  if (ids.length) {
    const found = await prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true } });
    if (found.length !== ids.length) throw httpError(400, "One or more users were not found");
  }
  await prisma.$transaction([
    prisma.couponEligibleUser.deleteMany({ where: { couponId: id } }),
    ...(ids.length
      ? [prisma.couponEligibleUser.createMany({ data: ids.map((userId) => ({ couponId: id, userId })) })]
      : []),
  ]);
  return getCoupon(id);
}

async function assignEligibleSocieties(id, societyIds, { skipReturn = false } = {}) {
  const coupon = await prisma.coupon.findUnique({
    where: { id },
    include: {
      _count: { select: { redemptions: true } },
      eligibleSocieties: { select: { societyId: true } },
    },
  });
  if (!coupon) throw httpError(404, "Coupon not found");

  const ids = Array.isArray(societyIds)
    ? [...new Set(societyIds.map((value) => String(value).trim()).filter(Boolean))]
    : [];

  const existingIds = coupon.eligibleSocieties.map((row) => row.societyId);
  const hasRedemptions = coupon._count.redemptions > 0;

  if (hasRedemptions && existingIds.length > 0 && ids.length === 0) {
    throw httpError(400, "Cannot remove society scope after the coupon has been used");
  }
  if (hasRedemptions && existingIds.length > 0) {
    const next = new Set(ids);
    for (const societyId of existingIds) {
      if (!next.has(societyId)) {
        throw httpError(400, "Cannot remove a society after the coupon has been used");
      }
    }
  }

  if (ids.length) {
    const found = await prisma.society.findMany({
      where: { id: { in: ids } },
      select: { id: true },
    });
    if (found.length !== ids.length) throw httpError(400, "One or more societies were not found");
  }

  await prisma.$transaction([
    prisma.couponEligibleSociety.deleteMany({ where: { couponId: id } }),
    ...(ids.length
      ? [
          prisma.couponEligibleSociety.createMany({
            data: ids.map((societyId) => ({ couponId: id, societyId })),
          }),
        ]
      : []),
  ]);

  if (skipReturn) return null;
  return getCoupon(id);
}

module.exports = {
  REASONS,
  money,
  normalizeCode,
  validateCoupon,
  applyCoupon,
  attachCouponRedemption,
  reverseCouponForOrder,
  couponErrorMessage,
  usageSummary,
  serializeCoupon,
  discountFor,
  startOfIstDay,
  startOfIstWeek,
  startOfIstMonth,
  createCoupon,
  listCoupons,
  getCoupon,
  updateCoupon,
  setCouponStatus,
  assignEligibleUsers,
  assignEligibleSocieties,
};
