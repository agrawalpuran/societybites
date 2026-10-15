const { parseDeliveryCharge } = require("./sellerFulfilment");
const { money: couponMoney } = require("./coupons");

const PENDING_STATUSES = new Set(["pending", "accepted", "preparing"]);

const DELIVERY_COLLECT_BY = Object.freeze({
  SELLER: "seller",
  DELIVERY_PERSON: "delivery_person",
});

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function orderIsCrossSociety(order) {
  const listing = order && order.items && order.items[0] && order.items[0].listing;
  if (!listing || !listing.societyId || !order.societyId) return false;
  return listing.societyId !== order.societyId;
}

function isOutsideSellerDeliveryOrder(order) {
  if (!order || (order.type || "regular") !== "regular") return false;
  if (!orderIsCrossSociety(order)) return false;
  return String(order.fulfilmentMethod || "").toLowerCase() === "seller_delivery";
}

/** @deprecated use isOutsideSellerDeliveryOrder */
function isEligibleDelayedDeliveryCharge(order) {
  return isOutsideSellerDeliveryOrder(order);
}

function isUpiFoodCashDeliverySplit(order) {
  if (!isOutsideSellerDeliveryOrder(order)) return false;
  return String(order.paymentMethod || "").toLowerCase() === "upi";
}

function isCodOutsideSellerDelivery(order) {
  if (!isOutsideSellerDeliveryOrder(order)) return false;
  return String(order.paymentMethod || "").toLowerCase() === "cash";
}

function isDeliveryChargePending(order) {
  if (!isOutsideSellerDeliveryOrder(order)) return false;
  return PENDING_STATUSES.has(order.status);
}

function isOutsideSellerDeliveryAtCreate({
  orderType,
  isCrossSocietyOrder,
  fulfilmentMethod,
}) {
  return (
    (orderType || "regular") === "regular" &&
    isCrossSocietyOrder &&
    String(fulfilmentMethod || "").toLowerCase() === "seller_delivery"
  );
}

function isEligibleDelayedDeliveryChargeAtCreate({
  orderType,
  isCrossSocietyOrder,
  paymentMethod,
  fulfilmentMethod,
}) {
  void paymentMethod;
  return isOutsideSellerDeliveryAtCreate({
    orderType,
    isCrossSocietyOrder,
    fulfilmentMethod,
  });
}

function parseActualDeliveryCharge(value) {
  if (value === undefined || value === null || value === "") {
    throw httpError(
      400,
      "Please enter the actual delivery charge before marking this order ready."
    );
  }
  return parseDeliveryCharge(value, "deliveryCharge");
}

function normalizeDeliveryCollectBy(value, fallback = DELIVERY_COLLECT_BY.SELLER) {
  const raw = String(value || fallback || DELIVERY_COLLECT_BY.SELLER)
    .trim()
    .toLowerCase();
  if (raw === DELIVERY_COLLECT_BY.SELLER || raw === "me") {
    return DELIVERY_COLLECT_BY.SELLER;
  }
  if (
    raw === DELIVERY_COLLECT_BY.DELIVERY_PERSON ||
    raw === "delivery" ||
    raw === "partner"
  ) {
    return DELIVERY_COLLECT_BY.DELIVERY_PERSON;
  }
  throw httpError(
    400,
    "deliveryCollectBy must be seller or delivery_person"
  );
}

function sellerDefaultDeliveryCollectBy(seller) {
  return normalizeDeliveryCollectBy(
    seller && seller.outsideDeliveryCollectBy,
    DELIVERY_COLLECT_BY.SELLER
  );
}

function couponDiscountFromOrder(order) {
  const redemption =
    order &&
    Array.isArray(order.couponRedemptions) &&
    order.couponRedemptions[0];
  if (!redemption) return 0;
  return couponMoney(redemption.discountAmount);
}

function computeOrderTotal({ subtotal, communityFee, deliveryCharge, couponDiscount }) {
  const base =
    Number(subtotal) + Number(communityFee || 0) + Number(deliveryCharge || 0);
  const discount = Number(couponDiscount || 0);
  return couponMoney(Math.max(0, base - discount));
}

function foodOnlyOrderTotal(order) {
  return computeOrderTotal({
    subtotal: order.subtotal,
    communityFee: order.communityFee,
    deliveryCharge: 0,
    couponDiscount: couponDiscountFromOrder(order),
  });
}

function isFoodUpiConfirmed(order) {
  const status = order.paymentStatus || "pending";
  return status === "seller_confirmed" || status === "paid";
}

function deliveryCashSettled(order) {
  const charge = Number(order.deliveryCharge || 0);
  if (charge <= 0) return true;
  return Boolean(order.deliveryCashConfirmedAt);
}

function assertCanCompleteOrder(order) {
  if (isCodOutsideSellerDelivery(order)) {
    if (order.paymentStatus !== "paid") {
      throw httpError(
        400,
        "Please confirm that payment has been received before completing this order."
      );
    }
    return;
  }
  if (isUpiFoodCashDeliverySplit(order)) {
    if (!isFoodUpiConfirmed(order)) {
      throw httpError(
        400,
        "Confirm UPI payment for the food amount before completing this order."
      );
    }
    if (!deliveryCashSettled(order)) {
      throw httpError(
        400,
        "Please confirm that the delivery fee has been received before completing this order."
      );
    }
    return;
  }
  if (String(order.paymentMethod || "").toLowerCase() === "cash") {
    if (order.paymentStatus !== "paid") {
      throw httpError(
        400,
        "Please confirm that payment has been received before completing this order."
      );
    }
  }
}

function upiPayableAmountForOrder(order) {
  if (!isUpiFoodCashDeliverySplit(order)) {
    return moneyOrZero(order.total);
  }
  if (isFoodUpiConfirmed(order)) return 0;
  return foodOnlyOrderTotal(order);
}

function moneyOrZero(value) {
  const n = Number(value);
  return Number.isFinite(n) ? couponMoney(n) : 0;
}

module.exports = {
  PENDING_STATUSES,
  DELIVERY_COLLECT_BY,
  orderIsCrossSociety,
  isOutsideSellerDeliveryOrder,
  isEligibleDelayedDeliveryCharge,
  isUpiFoodCashDeliverySplit,
  isCodOutsideSellerDelivery,
  isDeliveryChargePending,
  isOutsideSellerDeliveryAtCreate,
  isEligibleDelayedDeliveryChargeAtCreate,
  parseActualDeliveryCharge,
  normalizeDeliveryCollectBy,
  sellerDefaultDeliveryCollectBy,
  couponDiscountFromOrder,
  computeOrderTotal,
  foodOnlyOrderTotal,
  isFoodUpiConfirmed,
  deliveryCashSettled,
  assertCanCompleteOrder,
  upiPayableAmountForOrder,
};
