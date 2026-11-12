const { upiPayableAmountForOrder } = require("../delayedDeliveryCharge");

/**
 * Seller settlement is the amount captured by the gateway, minus the platform fee.
 * The fee stays with SocietyEats. Cashfree's own charges are not added back here.
 */
function sellerShareAmount(order) {
  const captured =
    order.gatewayAmount != null
      ? Number(order.gatewayAmount)
      : upiPayableAmountForOrder(order);
  const fee = Number(order.communityFee || 0);
  if (!Number.isFinite(captured) || !Number.isFinite(fee)) return 0;
  const share = Math.round((captured - fee) * 100) / 100;
  return share > 0 ? share : 0;
}

function isEligibleBalanceError(error) {
  const message = String((error && error.message) || "");
  return /eligible split balance/i.test(message);
}

module.exports = { sellerShareAmount, isEligibleBalanceError };
