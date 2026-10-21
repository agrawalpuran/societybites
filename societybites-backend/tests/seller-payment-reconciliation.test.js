require("dotenv").config();
const {
  isPaymentCollected,
  reconciliationPhase,
  canSendPaymentReminder,
  resolveReconciliationRange,
} = require("../lib/sellerPaymentReconciliation");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function order(overrides) {
  return {
    id: "o1",
    status: "accepted",
    paymentMethod: "upi",
    paymentStatus: "pending",
    total: 120,
    subtotal: 100,
    communityFee: 0,
    deliveryCharge: 0,
    items: [{ listing: { sellerId: "s1" } }],
    couponRedemptions: [],
    ...overrides,
  };
}

async function main() {
  const today = resolveReconciliationRange({ preset: "today" });
  assert(today.preset === "today", "today preset");
  const yesterday = resolveReconciliationRange({ preset: "yesterday" });
  assert(yesterday.fromYmd !== today.fromYmd, "yesterday differs");

  assert(reconciliationPhase(order({})) === "PENDING", "upi pending");
  assert(
    isPaymentCollected(
      order({ paymentStatus: "seller_confirmed", sellerConfirmedPaidAt: new Date() })
    ),
    "upi confirmed collected"
  );
  assert(
    reconciliationPhase(
      order({ paymentStatus: "seller_confirmed", sellerConfirmedPaidAt: new Date() })
    ) === "PAID",
    "paid phase"
  );
  assert(
    reconciliationPhase(order({ status: "cancelled" })) === "PENDING",
    "cancelled not collected"
  );
  assert(
    canSendPaymentReminder(order({})).ok === true,
    "pending can remind"
  );
  assert(
    canSendPaymentReminder(
      order({ paymentStatus: "paid", sellerConfirmedPaidAt: new Date() })
    ).ok === false,
    "paid cannot remind"
  );

  console.log("seller-payment-reconciliation.test.js passed");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
