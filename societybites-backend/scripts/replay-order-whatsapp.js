require("dotenv").config();
const prisma = require("../lib/prisma");
const { sendWhatsAppOrderNotification } = require("../lib/whatsappCloud");

async function main() {
  const orderNumber = process.argv[2];
  if (!orderNumber) {
    console.error("Usage: node scripts/replay-order-whatsapp.js SE-575246");
    process.exit(1);
  }
  const order = await prisma.order.findUnique({
    where: { orderNumber },
    include: {
      buyer: true,
      items: { include: { listing: { include: { seller: true } } } },
    },
  });
  if (!order) {
    console.error("Order not found");
    process.exit(1);
  }
  console.log("Replaying new_order for", orderNumber);
  const result = await sendWhatsAppOrderNotification(order);
  console.log("Result:", result);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
