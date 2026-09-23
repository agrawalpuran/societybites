/**
 * Buyer cancellation commitment rules.
 * UPI: until the buyer marks payment as paid.
 * COD (cash): until the seller accepts.
 */
function buyerCancelDeniedReason(order) {
  const method = String(order.paymentMethod || "upi").toLowerCase();
  const isCash = method === "cash";
  const status = order.status;

  if (isCash) {
    if (status === "pending") return null;
    return "Order cannot be cancelled after the seller accepts the order.";
  }

  const paymentLocked = ["buyer_marked_paid", "seller_confirmed", "paid"].includes(
    order.paymentStatus
  );
  if (paymentLocked) {
    return "Order cannot be cancelled after payment has been marked as paid.";
  }

  if (status === "pending" || status === "accepted") return null;

  return "Order cannot be cancelled after payment has been marked as paid.";
}

module.exports = { buyerCancelDeniedReason };
