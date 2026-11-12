/**
 * Creates one ₹1 Cashfree sandbox order when keys are present.
 * Does not move money. Paying it still needs a UPI app, and the split
 * runs only after Cashfree sends the signed webhook to this server.
 */
require("dotenv").config();

const { cashfreeConfig, createCashfreeUpiSession, resetPaymentFetch } = require("../lib/payments/cashfreeClient");

async function main() {
  const config = cashfreeConfig();
  if (!config.clientId || !config.clientSecret) {
    console.log("Cashfree sandbox check skipped: CASHFREE_CLIENT_ID or CASHFREE_CLIENT_SECRET is empty.");
    return;
  }
  if (config.env !== "sandbox") {
    console.log("Cashfree sandbox check skipped: CASHFREE_ENV is not sandbox.");
    return;
  }
  const orderNumber = `SE-SANDBOX-${Date.now()}`;
  const session = await createCashfreeUpiSession({
    order: {
      orderNumber,
      buyerId: "sandbox-buyer",
      buyer: { phone: "9999999999", name: "Sandbox Buyer" },
    },
    amount: 1,
    config,
  });
  resetPaymentFetch();
  console.log(`Cashfree sandbox order created: ${orderNumber}`);
  console.log(`UPI link returned: ${session.gatewayUpiLink ? "yes" : "no"}`);
  console.log(`QR payload returned: ${session.gatewayQrPayload ? "yes" : "no"}`);
  console.log("Pay ₹1 from that link or QR in a UPI app. The seller split runs after the signed webhook.");
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
