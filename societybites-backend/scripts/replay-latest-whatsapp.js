require("dotenv").config();
const prisma = require("../lib/prisma");
const { sendWhatsAppOrderNotification } = require("../lib/whatsappCloud");

async function main() {
  const order = await prisma.order.findFirst({
    orderBy: { createdAt: "desc" },
    include: {
      buyer: true,
      items: { include: { listing: { include: { seller: true } } } },
    },
  });
  if (!order) {
    console.log("No orders in DB");
    return;
  }
  console.log("Replaying for order", order.orderNumber, "seller phone", order.items[0]?.listing?.seller?.phone);
  const result = await sendWhatsAppOrderNotification(order);
  console.log("Result:", result);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
