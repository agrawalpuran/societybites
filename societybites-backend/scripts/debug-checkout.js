require("dotenv").config();
const prisma = require("../lib/prisma");
const { getPaymentProvider } = require("../lib/payments/paymentSetting");
const { beginCheckout } = require("../lib/payments/paymentService");

async function main() {
  const row = await prisma.appSetting.findUnique({
    where: { key: "payment_provider" },
  });
  console.log("app_setting", row);
  console.log("provider", await getPaymentProvider());
  console.log("CASHFREE_CLIENT_ID set?", Boolean(process.env.CASHFREE_CLIENT_ID));

  const order = await prisma.order.findFirst({
    where: { orderNumber: process.argv[2] || "SE-310965" },
  });
  if (!order) {
    console.log("order not found");
    return;
  }
  console.log("order status", order.status, "payment", order.paymentStatus);

  try {
    const session = await beginCheckout({
      orderId: order.id,
      userId: order.buyerId,
      returnOrigin: "http://localhost:3000",
    });
    console.log("checkout ok", session);
  } catch (err) {
    console.log("checkout fail", err.statusCode, err.message);
  }

  await prisma.$disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});